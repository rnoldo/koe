import AVFoundation
import CryptoKit
import Foundation

actor BaiduPlaybackPipeline {

    static let shared = BaiduPlaybackPipeline()

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let session: URLSession
    private let maxConcurrentDownloads = 1
    private let maxSegmentRetries = 8
    private var activeJobs: [String: Task<URL, Error>] = [:]

    private init() {
        rootDirectory = fileManager.temporaryDirectory.appendingPathComponent("BaiduPlaybackPipeline", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1200
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func preparePlayableMedia(
        video: Video,
        segments: [ResolvedBaiduSegment],
        headers: [String: String]
    ) async throws -> StreamableMedia {
        let context = try makeContext(video: video, segments: segments, headers: headers)
        let outputURL = try await runJob(for: context)
        return StreamableMedia(url: outputURL, httpHeaders: [:])
    }

    func prefetchPlayableMedia(
        video: Video,
        segments: [ResolvedBaiduSegment],
        headers: [String: String]
    ) async {
        do {
            let context = try makeContext(video: video, segments: segments, headers: headers)
            _ = try await runJob(for: context)
        } catch {
            NSLog("%@", "[KidsTV][Pipeline] Prefetch failed for \(video.title): \(error.localizedDescription)")
        }
    }

    private func makeContext(
        video: Video,
        segments: [ResolvedBaiduSegment],
        headers: [String: String]
    ) throws -> PipelineContext {
        guard !segments.isEmpty else {
            throw ScannerError.invalidURL
        }

        let cacheKey = makeCacheKey(video: video, segments: segments)
        let workingDirectory = rootDirectory.appendingPathComponent(cacheKey, isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        return PipelineContext(
            cacheKey: cacheKey,
            videoId: video.id,
            title: video.title,
            workingDirectory: workingDirectory,
            headers: headers,
            segments: segments
        )
    }

    private func runJob(for context: PipelineContext) async throws -> URL {
        if isPlayableAssetReady(at: context.remuxedAssetURL) {
            NSLog("%@", "[KidsTV][Pipeline] Reuse remuxed asset \(context.remuxedAssetURL.lastPathComponent)")
            return context.remuxedAssetURL
        }

        if let existing = activeJobs[context.cacheKey] {
            return try await awaitJob(existing, cacheKey: context.cacheKey)
        }

        NSLog("%@", "[KidsTV][Pipeline] Prepare cache key=\(context.cacheKey) title=\(context.title) segments=\(context.segments.count)")
        let task = Task<URL, Error> {
            try await self.buildPlayableAsset(for: context)
        }
        activeJobs[context.cacheKey] = task
        return try await awaitJob(task, cacheKey: context.cacheKey)
    }

    private func awaitJob(_ task: Task<URL, Error>, cacheKey: String) async throws -> URL {
        defer {
            activeJobs[cacheKey] = nil
        }
        return try await task.value
    }

    private func buildPlayableAsset(for context: PipelineContext) async throws -> URL {
        try await restoreOrCreateManifest(for: context)
        try await materializeAllSegments(for: context)
        let concatURL = try writeConcatFile(for: context)
        do {
            let remuxedURL = try await exportMergedAsset(for: context)
            try writeReadyMarker(for: context, outputURL: remuxedURL)
            NSLog("%@", "[KidsTV][Pipeline] Ready remuxed=\(remuxedURL.lastPathComponent) dir=\(context.workingDirectory.lastPathComponent)")
            return remuxedURL
        } catch {
            NSLog("%@", "[KidsTV][Pipeline] Remux fallback to concat after error: \(error.localizedDescription)")
            try writeReadyMarker(for: context, outputURL: concatURL)
            return concatURL
        }
    }

    private func restoreOrCreateManifest(for context: PipelineContext) async throws {
        let manifestURL = context.manifestURL
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PipelineManifest.self, from: data)
            guard manifest.cacheKey == context.cacheKey, manifest.segmentCount == context.segments.count else {
                try? fileManager.removeItem(at: context.workingDirectory)
                try fileManager.createDirectory(at: context.workingDirectory, withIntermediateDirectories: true)
                return try await restoreOrCreateManifest(for: context)
            }
            return
        }

        let entries = context.segments.enumerated().map { index, segment in
            PipelineManifest.Entry(
                index: index,
                url: segment.url.absoluteString,
                duration: segment.duration,
                fileName: Self.segmentFileName(for: index)
            )
        }
        let manifest = PipelineManifest(
            cacheKey: context.cacheKey,
            createdAt: Date(),
            videoId: context.videoId,
            title: context.title,
            segmentCount: context.segments.count,
            entries: entries
        )
        try writeManifest(manifest, to: manifestURL)
    }

    private func materializeAllSegments(for context: PipelineContext) async throws {
        let pending = context.segments.enumerated().filter { index, _ in
            !isPlayableAssetReady(at: context.segmentFileURL(index: index))
        }

        if pending.isEmpty {
            NSLog("%@", "[KidsTV][Pipeline] Cache hit segments=\(context.segments.count)")
            return
        }

        NSLog("%@", "[KidsTV][Pipeline] Download missing=\(pending.count)/\(context.segments.count)")

        let maxRetries = maxSegmentRetries
        var cursor = 0
        while cursor < pending.count {
            let batchEnd = min(cursor + maxConcurrentDownloads, pending.count)
            let batch = Array(pending[cursor..<batchEnd])

            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, segment) in batch {
                    let destination = context.segmentFileURL(index: index)
                    let headers = context.headers
                    group.addTask { [session] in
                        try await Self.downloadSegment(
                            session: session,
                            url: segment.url,
                            headers: headers,
                            destination: destination,
                            index: index,
                            total: context.segments.count,
                            maxRetries: maxRetries
                        )
                    }
                }
                try await group.waitForAll()
            }

            cursor = batchEnd
            NSLog("%@", "[KidsTV][Pipeline] Downloaded \(cursor)/\(pending.count) missing segments")
        }
    }

    private func writeConcatFile(for context: PipelineContext) throws -> URL {
        let concatURL = context.concatURL
        var lines = ["ffconcat version 1.0"]
        for (index, segment) in context.segments.enumerated() {
            let fileURL = context.segmentFileURL(index: index)
            guard isPlayableAssetReady(at: fileURL) else {
                throw ScannerError.serverError("Missing local segment \(index)")
            }
            lines.append("file \(quotedConcatPath(fileURL.lastPathComponent))")
            if segment.duration > 0 {
                lines.append("duration \(segment.duration)")
            }
        }
        try lines.joined(separator: "\n").write(to: concatURL, atomically: true, encoding: .utf8)
        return concatURL
    }

    private func exportMergedAsset(for context: PipelineContext) async throws -> URL {
        let outputURL = context.remuxedAssetURL
        if isPlayableAssetReady(at: outputURL) {
            return outputURL
        }

        let temporaryURL = outputURL.appendingPathExtension("part")
        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        var compositionVideoTrack: AVMutableCompositionTrack?
        var compositionAudioTrack: AVMutableCompositionTrack?

        for index in context.segments.indices {
            let assetURL = context.segmentFileURL(index: index)
            let asset = AVURLAsset(url: assetURL)
            let duration = try await asset.load(.duration)
            if !duration.isNumeric || duration <= .zero {
                continue
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let sourceVideoTrack = videoTracks.first {
                if compositionVideoTrack == nil {
                    compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try await compositionVideoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
                compositionVideoTrack?.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first {
                if compositionAudioTrack == nil {
                    compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try await compositionAudioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        guard cursor > .zero else {
            throw ScannerError.serverError("No media tracks exported")
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ScannerError.serverError("Failed to create export session")
        }
        exportSession.outputURL = temporaryURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportSession.exportAsync()

        guard isPlayableAssetReady(at: temporaryURL) else {
            throw ScannerError.serverError("Exported asset missing")
        }

        try? fileManager.removeItem(at: outputURL)
        try fileManager.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
    }

    private func writeReadyMarker(for context: PipelineContext, outputURL: URL) throws {
        let readyURL = context.readyURL
        let contents = "\(Date().timeIntervalSince1970)\n\(outputURL.lastPathComponent)"
        try contents.write(to: readyURL, atomically: true, encoding: .utf8)
    }

    private func writeManifest(_ manifest: PipelineManifest, to url: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func isPlayableAssetReady(at url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize > 1024
        else {
            return false
        }
        return true
    }

    private func quotedConcatPath(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func makeCacheKey(video: Video, segments: [ResolvedBaiduSegment]) -> String {
        let seed = ([video.id, video.remotePath] + segments.map(\.url.absoluteString)).joined(separator: "|")
        let digest = Insecure.MD5.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func segmentFileName(for index: Int) -> String {
        String(format: "%03d.mp4", index)
    }

    private static func downloadSegment(
        session: URLSession,
        url: URL,
        headers: [String: String],
        destination: URL,
        index: Int,
        total: Int,
        maxRetries: Int
    ) async throws {
        let temporaryURL = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: temporaryURL)

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                NSLog("%@", "[KidsTV][Pipeline] Segment \(index + 1)/\(total) attempt \(attempt)")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw HTTPError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw HTTPError.badStatus(http.statusCode, data)
                }
                guard data.count > 1024 else {
                    throw ScannerError.serverError("Segment \(index) too small")
                }

                try data.write(to: temporaryURL, options: .atomic)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                return
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                if attempt == maxRetries {
                    throw error
                }
                let backoff = UInt64(attempt * 700_000_000)
                NSLog("%@", "[KidsTV][Pipeline] Segment \(index + 1) retry after error: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: backoff)
            }
        }
    }
}

struct ResolvedBaiduSegment {
    let url: URL
    let duration: Double
}

private struct PipelineContext {
    let cacheKey: String
    let videoId: String
    let title: String
    let workingDirectory: URL
    let headers: [String: String]
    let segments: [ResolvedBaiduSegment]

    var manifestURL: URL {
        workingDirectory.appendingPathComponent("manifest.json")
    }

    var concatURL: URL {
        workingDirectory.appendingPathComponent("stream.ffconcat")
    }

    var remuxedAssetURL: URL {
        workingDirectory.appendingPathComponent("stream.mp4")
    }

    var readyURL: URL {
        workingDirectory.appendingPathComponent(".ready")
    }

    func segmentFileURL(index: Int) -> URL {
        workingDirectory.appendingPathComponent(BaiduPlaybackPipeline.segmentFileName(for: index))
    }
}

private struct PipelineManifest: Codable {
    struct Entry: Codable {
        let index: Int
        let url: String
        let duration: Double
        let fileName: String
    }

    let cacheKey: String
    let createdAt: Date
    let videoId: String
    let title: String
    let segmentCount: Int
    let entries: [Entry]
}

private extension AVAssetExportSession {
    func exportAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportAsynchronously {
                switch self.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: self.error ?? ScannerError.serverError("Export failed"))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: ScannerError.serverError("Unexpected export status \(self.status.rawValue)"))
                }
            }
        }
    }
}
