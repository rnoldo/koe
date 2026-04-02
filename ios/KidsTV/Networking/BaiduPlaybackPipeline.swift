import CryptoKit
import Foundation
import Libavcodec
import Libavformat
import Libavutil

actor BaiduPlaybackPipeline {

    static let shared = BaiduPlaybackPipeline()

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let session: URLSession
    private let maxSegmentRetries = 8
    private let startupBufferSegmentCount = 2
    private let startupBufferDuration: Double = 4
    private let startupBufferTimeout: TimeInterval = 120
    private let startupPrimeConcurrency = 3
    private let prefetchAheadDuration: Double = 40
    private let keepBehindDuration: Double = 12
    private let prefetchAheadBytes = 96 * 1024 * 1024
    private let maxRetainedBytes = 160 * 1024 * 1024
    private var runtimes: [String: PipelineRuntime] = [:]

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
        guard !segments.isEmpty else {
            throw ScannerError.invalidURL
        }

        let cacheKey = makeCacheKey(video: video, segments: segments)
        let workingDirectory = rootDirectory.appendingPathComponent(cacheKey, isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let context = PipelineContext(
            cacheKey: cacheKey,
            videoId: video.id,
            title: video.title,
            workingDirectory: workingDirectory,
            headers: headers,
            segments: segments
        )

        try? fileManager.removeItem(at: context.logURL)
        log("Prepare cache key=\(cacheKey) title=\(video.title) segments=\(segments.count)", for: context)
        try await restoreOrCreateManifest(for: context)
        BaiduMPVStreamRegistry.shared.registerSession(
            cacheKey: context.cacheKey,
            segments: context.segments.enumerated().map { index, segment in
                BaiduMPVSegmentDescriptor(
                    index: index,
                    url: segment.url,
                    localFileURL: context.transmuxFileURL(index: index),
                    duration: segment.duration
                )
            }
        )

        let startupTarget = startupTargetIndex(for: context)
        try await hydrateReadySegmentsFromDisk(for: context)
        try await primeStartupBuffer(for: context, startupTarget: startupTarget)
        replaceRuntime(for: context, startupTarget: startupTarget)
        syncFinishedStateIfNeeded(cacheKey: context.cacheKey)
        requestRollingPrefetch(cacheKey: context.cacheKey, currentIndex: 0)
        startDownloaderIfNeeded(cacheKey: context.cacheKey)
        try await waitForStartupBuffer(for: context)
        try writeReadyMarker(for: context)

        let streamURL = URL(string: "kidstv://session/\(context.cacheKey)")!
        NSLog("%@", "[KidsTV][Pipeline] Ready streaming url=\(streamURL.absoluteString) dir=\(workingDirectory.lastPathComponent)")
        return StreamableMedia(url: streamURL, httpHeaders: [:])
    }

    func requestRollingPrefetch(cacheKey: String, currentIndex: Int) {
        guard var runtime = runtimes[cacheKey] else { return }
        guard runtime.failedMessage == nil else { return }

        runtime.consumedIndex = max(runtime.consumedIndex, currentIndex)
        let prefetchTarget = prefetchTargetIndex(for: runtime.context, currentIndex: currentIndex)
        runtime.requestedThrough = max(runtime.requestedThrough, prefetchTarget)
        evictOldSegmentsIfNeeded(runtime: &runtime)
        runtimes[cacheKey] = runtime
        startDownloaderIfNeeded(cacheKey: cacheKey)
    }

    func closeSession(cacheKey: String) {
        guard let runtime = runtimes.removeValue(forKey: cacheKey) else { return }
        runtime.downloaderTask?.cancel()
        NSLog("%@", "[KidsTV][Pipeline] Close session cacheKey=\(cacheKey)")
    }

    private func waitForStartupBuffer(for context: PipelineContext) async throws {
        let startedAt = Date()

        while true {
            try Task.checkCancellation()

            let status = bufferedPrefixStatus(for: context)
            if isStartupReady(status: status, totalSegments: context.segments.count) {
                log(
                    "Startup buffer ready segments=\(status.segmentCount)/\(context.segments.count) duration=\(Int(status.duration))s elapsed=\(String(format: "%.1f", Date().timeIntervalSince(startedAt)))s",
                    for: context
                )
                return
            }

            if let message = runtimes[context.cacheKey]?.failedMessage {
                log("Startup aborted: \(message)", for: context)
                throw ScannerError.serverError(message)
            }

            if Date().timeIntervalSince(startedAt) > startupBufferTimeout {
                throw ScannerError.serverError("Startup buffer timeout after \(Int(startupBufferTimeout))s")
            }

            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func bufferedPrefixStatus(for context: PipelineContext) -> BufferedPrefixStatus {
        var count = 0
        var duration: Double = 0

        for (index, segment) in context.segments.enumerated() {
            guard isSegmentReady(at: context.transmuxFileURL(index: index)) else { break }
            count += 1
            duration += max(0, segment.duration)
        }

        return BufferedPrefixStatus(segmentCount: count, duration: duration)
    }

    private func isStartupReady(status: BufferedPrefixStatus, totalSegments: Int) -> Bool {
        guard totalSegments > 0 else { return false }
        if status.segmentCount >= totalSegments {
            return true
        }
        return status.segmentCount >= startupBufferSegmentCount && status.duration >= startupBufferDuration
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
                fileName: Self.transmuxFileName(for: index)
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

    private func hydrateReadySegmentsFromDisk(for context: PipelineContext) async throws {
        var hydratedCount = 0
        var hydratedDuration: Double = 0
        let targetCount = min(startupBufferSegmentCount, context.segments.count)
        let targetDuration = min(startupBufferDuration, context.segments.reduce(0) { $0 + max(0, $1.duration) })

        for index in context.segments.indices {
            if hydratedCount >= targetCount && hydratedDuration >= targetDuration {
                break
            }
            guard let fileSize = try await ensureTransmuxReadyOnDisk(for: context, index: index, allowTransmuxFromSource: true) else {
                break
            }
            BaiduMPVStreamRegistry.shared.markSegmentReady(cacheKey: context.cacheKey, index: index, byteCount: fileSize)
            hydratedCount += 1
            hydratedDuration += max(0, context.segments[index].duration)
        }

        for index in context.segments.indices {
            guard let fileSize = try await ensureTransmuxReadyOnDisk(for: context, index: index, allowTransmuxFromSource: false) else {
                continue
            }
            BaiduMPVStreamRegistry.shared.markSegmentReady(cacheKey: context.cacheKey, index: index, byteCount: fileSize)
        }
    }

    private func primeStartupBuffer(for context: PipelineContext, startupTarget: Int) async throws {
        guard startupTarget >= 0 else { return }

        let missing = Array(0...startupTarget).filter { !isSegmentReady(at: context.transmuxFileURL(index: $0)) }
        guard !missing.isEmpty else { return }

        log("Prime startup buffer target=\(startupTarget + 1) missing=\(missing.count) concurrency=\(startupPrimeConcurrency)", for: context)

        let concurrency = min(startupPrimeConcurrency, missing.count)
        let retries = maxSegmentRetries
        var iterator = missing.makeIterator()

        try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for _ in 0..<concurrency {
                guard let index = iterator.next() else { break }
                group.addTask { [session] in
                    try await Self.downloadSegment(
                        session: session,
                        url: context.segments[index].url,
                        headers: context.headers,
                        sourceURL: context.segmentFileURL(index: index),
                        outputURL: context.transmuxFileURL(index: index),
                        logURL: context.logURL,
                        index: index,
                        total: context.segments.count,
                        maxRetries: retries
                    )
                    let fileSize = try Self.fileSizeForURL(context.transmuxFileURL(index: index))
                    return (index, fileSize)
                }
            }

            while let (index, fileSize) = try await group.next() {
                BaiduMPVStreamRegistry.shared.markSegmentReady(cacheKey: context.cacheKey, index: index, byteCount: fileSize)
                log("Primed segment \(index + 1) bytes=\(fileSize)", for: context)

                guard let nextIndex = iterator.next() else { continue }
                group.addTask { [session] in
                    try await Self.downloadSegment(
                        session: session,
                        url: context.segments[nextIndex].url,
                        headers: context.headers,
                        sourceURL: context.segmentFileURL(index: nextIndex),
                        outputURL: context.transmuxFileURL(index: nextIndex),
                        logURL: context.logURL,
                        index: nextIndex,
                        total: context.segments.count,
                        maxRetries: retries
                    )
                    let fileSize = try Self.fileSizeForURL(context.transmuxFileURL(index: nextIndex))
                    return (nextIndex, fileSize)
                }
            }
        }
    }

    private func startupTargetIndex(for context: PipelineContext) -> Int {
        guard !context.segments.isEmpty else { return -1 }

        var duration: Double = 0
        var count = 0
        for (index, segment) in context.segments.enumerated() {
            count += 1
            duration += max(0, segment.duration)
            if count >= startupBufferSegmentCount && duration >= startupBufferDuration {
                return index
            }
        }
        return context.segments.count - 1
    }

    private func prefetchTargetIndex(for context: PipelineContext, currentIndex: Int) -> Int {
        guard !context.segments.isEmpty else { return -1 }

        var clampedIndex = min(max(0, currentIndex), context.segments.count - 1)
        var bufferedDuration: Double = 0
        let averageBytes = averageReadySegmentBytes(for: context)
        var bufferedBytes = 0

        while clampedIndex < context.segments.count - 1 {
            bufferedDuration += max(0, context.segments[clampedIndex].duration)
            bufferedBytes += estimatedTransmuxBytes(for: context, index: clampedIndex, fallback: averageBytes)
            if bufferedDuration >= prefetchAheadDuration || bufferedBytes >= prefetchAheadBytes {
                break
            }
            clampedIndex += 1
        }
        return clampedIndex
    }

    private func replaceRuntime(for context: PipelineContext, startupTarget: Int) {
        if let old = runtimes[context.cacheKey] {
            old.downloaderTask?.cancel()
        }

        let nextIndex = firstMissingTransmuxIndex(for: context)
        let runtime = PipelineRuntime(
            context: context,
            requestedThrough: max(startupTarget, 0),
            consumedIndex: 0,
            nextDownloadIndex: nextIndex,
            evictedThroughIndex: -1,
            failedMessage: nil,
            finished: nextIndex >= context.segments.count,
            downloaderTask: nil
        )
        runtimes[context.cacheKey] = runtime
    }

    private func firstMissingTransmuxIndex(for context: PipelineContext) -> Int {
        for index in context.segments.indices {
            if !isSegmentReady(at: context.transmuxFileURL(index: index)) {
                return index
            }
        }
        return context.segments.count
    }

    private func startDownloaderIfNeeded(cacheKey: String) {
        guard var runtime = runtimes[cacheKey] else { return }
        guard runtime.downloaderTask == nil else { return }
        guard runtime.failedMessage == nil else { return }

        runtime.downloaderTask = Task { [weak self] in
            await self?.runDownloaderLoop(cacheKey: cacheKey)
        }
        runtimes[cacheKey] = runtime
    }

    private func runDownloaderLoop(cacheKey: String) async {
        while !Task.isCancelled {
            let command = nextDownloadCommand(cacheKey: cacheKey)
            switch command {
            case .wait:
                try? await Task.sleep(for: .milliseconds(150))
            case .finish:
                BaiduMPVStreamRegistry.shared.markSessionFinished(cacheKey: cacheKey)
                if let runtime = runtimes[cacheKey] {
                    log("Downloader finished after segment \(runtime.nextDownloadIndex)/\(runtime.context.segments.count)", for: runtime.context)
                }
                clearDownloader(cacheKey: cacheKey, finished: true)
                return
            case .stop:
                clearDownloader(cacheKey: cacheKey, finished: false)
                return
            case .download(let context, let index):
                do {
                    log("Materialize segment \(index + 1)/\(context.segments.count)", for: context)
                    try await Self.downloadSegment(
                        session: session,
                        url: context.segments[index].url,
                        headers: context.headers,
                        sourceURL: context.segmentFileURL(index: index),
                        outputURL: context.transmuxFileURL(index: index),
                        logURL: context.logURL,
                        index: index,
                        total: context.segments.count,
                        maxRetries: maxSegmentRetries
                    )
                    let outputURL = context.transmuxFileURL(index: index)
                    let fileSize = try segmentFileSize(at: outputURL)
                    guard fileSize > 1024 else {
                        throw ScannerError.serverError("Segment \(index + 1) exported empty")
                    }
                    log("Segment \(index + 1) ready bytes=\(fileSize)", for: context)
                    BaiduMPVStreamRegistry.shared.markSegmentReady(cacheKey: context.cacheKey, index: index, byteCount: fileSize)
                    syncFinishedStateIfNeeded(cacheKey: cacheKey)
                } catch {
                    let message = "Segment \(index + 1) failed: \(error.localizedDescription)"
                    log(message, for: context)
                    setRuntimeFailure(cacheKey: cacheKey, message: message)
                    return
                }
            }
        }

        clearDownloader(cacheKey: cacheKey, finished: false)
    }

    private func nextDownloadCommand(cacheKey: String) -> DownloadCommand {
        guard var runtime = runtimes[cacheKey] else { return .stop }
        if runtime.failedMessage != nil { return .stop }
        if runtime.finished { return .stop }

        let total = runtime.context.segments.count
        if runtime.nextDownloadIndex >= total {
            if runtime.requestedThrough >= total - 1 {
                runtime.finished = true
                runtimes[cacheKey] = runtime
                return .finish
            }
            return .wait
        }

        if runtime.nextDownloadIndex > runtime.requestedThrough {
            return .wait
        }

        let index = runtime.nextDownloadIndex
        runtime.nextDownloadIndex += 1
        runtimes[cacheKey] = runtime
        return .download(runtime.context, index)
    }

    private func clearDownloader(cacheKey: String, finished: Bool) {
        guard var runtime = runtimes[cacheKey] else { return }
        runtime.downloaderTask = nil
        if finished {
            runtime.finished = true
        }
        runtimes[cacheKey] = runtime
    }

    private func setRuntimeFailure(cacheKey: String, message: String) {
        guard var runtime = runtimes[cacheKey] else { return }
        runtime.failedMessage = message
        runtime.downloaderTask?.cancel()
        runtime.downloaderTask = nil
        runtimes[cacheKey] = runtime
        BaiduMPVStreamRegistry.shared.markSessionFailed(cacheKey: cacheKey, message: message)
    }

    private func evictOldSegmentsIfNeeded(runtime: inout PipelineRuntime) {
        let keepFloor = keepFloorIndex(for: runtime.context, consumedIndex: runtime.consumedIndex)
        let start = max(0, runtime.evictedThroughIndex + 1)
        guard start < runtime.context.segments.count else { return }

        var retainedBytes = retainedBufferedBytes(for: runtime.context, startIndex: start)
        var newEvictedThrough = runtime.evictedThroughIndex

        if start < keepFloor {
            for index in start..<keepFloor {
                retainedBytes = max(0, retainedBytes - evictSegment(at: index, in: runtime.context))
                newEvictedThrough = index
            }
        }

        let maxBudgetFloor = min(runtime.consumedIndex, runtime.context.segments.count - 1)
        var candidate = max(keepFloor, newEvictedThrough + 1)
        while retainedBytes > maxRetainedBytes && candidate < maxBudgetFloor {
            retainedBytes = max(0, retainedBytes - evictSegment(at: candidate, in: runtime.context))
            newEvictedThrough = candidate
            candidate += 1
        }

        if newEvictedThrough > runtime.evictedThroughIndex {
            runtime.evictedThroughIndex = newEvictedThrough
        }
    }

    private func keepFloorIndex(for context: PipelineContext, consumedIndex: Int) -> Int {
        guard !context.segments.isEmpty else { return 0 }

        let clampedConsumed = min(max(0, consumedIndex), context.segments.count - 1)
        var retainedDuration: Double = 0
        var floorIndex = clampedConsumed

        while floorIndex > 0 {
            retainedDuration += max(0, context.segments[floorIndex].duration)
            if retainedDuration >= keepBehindDuration {
                break
            }
            floorIndex -= 1
        }

        return max(0, floorIndex)
    }

    private func retainedBufferedBytes(for context: PipelineContext, startIndex: Int) -> Int {
        guard startIndex < context.segments.count else { return 0 }

        var total = 0
        for index in startIndex..<context.segments.count {
            let tsURL = context.transmuxFileURL(index: index)
            let sourceURL = context.segmentFileURL(index: index)
            total += ((try? segmentFileSize(at: tsURL)) ?? 0)
            total += ((try? segmentFileSize(at: sourceURL)) ?? 0)
        }
        return total
    }

    private func averageReadySegmentBytes(for context: PipelineContext) -> Int {
        var totalBytes = 0
        var count = 0

        for index in context.segments.indices {
            let tsURL = context.transmuxFileURL(index: index)
            guard let size = try? segmentFileSize(at: tsURL), size > 0 else { continue }
            totalBytes += size
            count += 1
        }

        guard count > 0 else { return 2 * 1024 * 1024 }
        return max(totalBytes / count, 256 * 1024)
    }

    private func estimatedTransmuxBytes(for context: PipelineContext, index: Int, fallback: Int) -> Int {
        let tsURL = context.transmuxFileURL(index: index)
        if let size = try? segmentFileSize(at: tsURL), size > 0 {
            return size
        }
        return fallback
    }

    private func ensureTransmuxReadyOnDisk(
        for context: PipelineContext,
        index: Int,
        allowTransmuxFromSource: Bool
    ) async throws -> Int? {
        let sourceURL = context.segmentFileURL(index: index)
        let outputURL = context.transmuxFileURL(index: index)

        if !isSegmentReady(at: outputURL) {
            guard allowTransmuxFromSource, isSegmentReady(at: sourceURL) else { return nil }
            try await Self.materializeSegmentForPlayback(sourceURL: sourceURL, outputURL: outputURL, detectedKind: nil)
        }

        guard isSegmentReady(at: outputURL) else { return nil }
        let fileSize = try segmentFileSize(at: outputURL)
        return fileSize > 1024 ? fileSize : nil
    }

    @discardableResult
    private func evictSegment(at index: Int, in context: PipelineContext) -> Int {
        let tsURL = context.transmuxFileURL(index: index)
        let sourceURL = context.segmentFileURL(index: index)
        let segmentBytes = ((try? segmentFileSize(at: tsURL)) ?? 0) + ((try? segmentFileSize(at: sourceURL)) ?? 0)
        try? fileManager.removeItem(at: sourceURL)
        try? fileManager.removeItem(at: tsURL)
        BaiduMPVStreamRegistry.shared.markSegmentEvicted(cacheKey: context.cacheKey, index: index)
        return segmentBytes
    }

    private func segmentFileSize(at url: URL) throws -> Int {
        try Self.fileSizeForURL(url)
    }

    private func syncFinishedStateIfNeeded(cacheKey: String) {
        guard let runtime = runtimes[cacheKey], runtime.finished else { return }
        BaiduMPVStreamRegistry.shared.markSessionFinished(cacheKey: cacheKey)
    }

    private func writeReadyMarker(for context: PipelineContext) throws {
        let readyURL = context.readyURL
        let contents = "\(Date().timeIntervalSince1970)"
        try contents.write(to: readyURL, atomically: true, encoding: .utf8)
        log("Ready marker written", for: context)
    }

    private func writeManifest(_ manifest: PipelineManifest, to url: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func isSegmentReady(at url: URL) -> Bool {
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

    private func makeCacheKey(video: Video, segments: [ResolvedBaiduSegment]) -> String {
        let seed = ([video.id, video.remotePath] + segments.map(\.url.absoluteString)).joined(separator: "|")
        let digest = Insecure.MD5.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func log(_ message: String, for context: PipelineContext) {
        let line = "[KidsTV][Pipeline] \(message)"
        NSLog("%@", line)
        Self.appendLog(line, to: context.logURL)
    }

    static func segmentFileName(for index: Int) -> String {
        String(format: "%03d.mp4", index)
    }

    static func transmuxFileName(for index: Int) -> String {
        String(format: "%03d.ts", index)
    }

    private static func downloadSegment(
        session: URLSession,
        url: URL,
        headers: [String: String],
        sourceURL: URL,
        outputURL: URL,
        logURL: URL,
        index: Int,
        total: Int,
        maxRetries: Int
    ) async throws {
        let temporaryURL = sourceURL.appendingPathExtension("part")
        let temporaryOutputURL = outputURL.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: temporaryURL)
        try? FileManager.default.removeItem(at: temporaryOutputURL)

        if FileManager.default.fileExists(atPath: outputURL.path),
           isReadyFile(outputURL) {
            return
        }

        if FileManager.default.fileExists(atPath: sourceURL.path),
           isReadyFile(sourceURL) {
            do {
                try await materializeSegmentForPlayback(sourceURL: sourceURL, outputURL: outputURL, detectedKind: nil)
                return
            } catch {
                appendLog("[KidsTV][Pipeline] Cached source remux retry after error: \(error.localizedDescription)", to: logURL)
                try? FileManager.default.removeItem(at: sourceURL)
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                appendLog("[KidsTV][Pipeline] Segment \(index + 1)/\(total) attempt \(attempt)", to: logURL)
                let startedAt = Date()
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

                let detectedKind = SegmentPayloadKind.detect(in: data)
                let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
                let speedKBps = Int((Double(data.count) / 1024.0) / elapsed)
                appendLog(
                    "[KidsTV][Pipeline] Segment \(index + 1) kind=\(detectedKind.description) bytes=\(data.count) elapsed=\(String(format: "%.2f", elapsed))s speed=\(speedKBps)KB/s",
                    to: logURL
                )
                try await materializeDownloadedSegment(
                    data: data,
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    temporarySourceURL: temporaryURL,
                    temporaryOutputURL: temporaryOutputURL,
                    detectedKind: detectedKind
                )
                return
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                try? FileManager.default.removeItem(at: temporaryOutputURL)
                if attempt == maxRetries {
                    throw error
                }
                let backoff = UInt64(attempt * 700_000_000)
                appendLog("[KidsTV][Pipeline] Segment \(index + 1) retry after error: \(error.localizedDescription)", to: logURL)
                try await Task.sleep(nanoseconds: backoff)
            }
        }
    }

    private static func transmuxSegmentToTS(sourceURL: URL, outputURL: URL) async throws {
        try await FFmpegTransmuxer.transmuxToTransportStream(sourceURL: sourceURL, outputURL: outputURL)
    }

    private static func isReadyFile(_ url: URL) -> Bool {
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

    private static func materializeDownloadedSegment(
        data: Data,
        sourceURL: URL,
        outputURL: URL,
        temporarySourceURL: URL,
        temporaryOutputURL: URL,
        detectedKind: SegmentPayloadKind
    ) async throws {
        switch detectedKind {
        case .transportStream:
            try? FileManager.default.removeItem(at: outputURL)
            try data.write(to: temporaryOutputURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryOutputURL, to: outputURL)
            try? FileManager.default.removeItem(at: sourceURL)
        case .mp4Like, .unknownBinary:
            try? FileManager.default.removeItem(at: sourceURL)
            try data.write(to: temporarySourceURL, options: .atomic)
            try FileManager.default.moveItem(at: temporarySourceURL, to: sourceURL)
            try await transmuxSegmentToTS(sourceURL: sourceURL, outputURL: outputURL)
        case .json(let preview), .text(let preview):
            throw ScannerError.serverError("Baidu segment returned non-media payload: \(preview)")
        }
    }

    private static func materializeSegmentForPlayback(
        sourceURL: URL,
        outputURL: URL,
        detectedKind: SegmentPayloadKind?
    ) async throws {
        let kind = detectedKind ?? detectSegmentKind(at: sourceURL)
        switch kind {
        case .transportStream:
            if sourceURL.path != outputURL.path {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: sourceURL, to: outputURL)
            }
        case .mp4Like, .unknownBinary:
            try await transmuxSegmentToTS(sourceURL: sourceURL, outputURL: outputURL)
        case .json(let preview), .text(let preview):
            throw ScannerError.serverError("Baidu segment returned non-media payload: \(preview)")
        }
    }

    private static func detectSegmentKind(at url: URL) -> SegmentPayloadKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknownBinary }
        defer { try? handle.close() }
        let sample = try? handle.read(upToCount: 4096)
        return SegmentPayloadKind.detect(in: sample ?? Data())
    }

    private static func appendLog(_ line: String, to logURL: URL) {
        let payload = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
                return
            }
        }
        try? payload.write(to: logURL, options: .atomic)
    }

    private static func fileSizeForURL(_ url: URL) throws -> Int {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attrs[.size] as? NSNumber)?.intValue
        else {
            throw ScannerError.serverError("Unable to read segment size")
        }
        return size
    }
}

private extension BaiduPlaybackPipeline {
    struct PipelineRuntime {
        let context: PipelineContext
        var requestedThrough: Int
        var consumedIndex: Int
        var nextDownloadIndex: Int
        var evictedThroughIndex: Int
        var failedMessage: String?
        var finished: Bool
        var downloaderTask: Task<Void, Never>?
    }

    enum DownloadCommand {
        case wait
        case finish
        case stop
        case download(PipelineContext, Int)
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
    var readyURL: URL {
        workingDirectory.appendingPathComponent(".ready")
    }
    var logURL: URL {
        workingDirectory.appendingPathComponent("pipeline.log")
    }

    func segmentFileURL(index: Int) -> URL {
        workingDirectory.appendingPathComponent(BaiduPlaybackPipeline.segmentFileName(for: index))
    }

    func transmuxFileURL(index: Int) -> URL {
        workingDirectory.appendingPathComponent(BaiduPlaybackPipeline.transmuxFileName(for: index))
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

private struct BufferedPrefixStatus {
    let segmentCount: Int
    let duration: Double
}

private enum SegmentPayloadKind {
    case transportStream
    case mp4Like
    case json(String)
    case text(String)
    case unknownBinary

    var description: String {
        switch self {
        case .transportStream:
            return "transport-stream"
        case .mp4Like:
            return "mp4-like"
        case .json:
            return "json"
        case .text:
            return "text"
        case .unknownBinary:
            return "unknown-binary"
        }
    }

    static func detect(in data: Data) -> SegmentPayloadKind {
        if looksLikeTransportStream(data) {
            return .transportStream
        }
        if looksLikeMP4(data) {
            return .mp4Like
        }

        if let text = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            if text.hasPrefix("{") || text.hasPrefix("[") {
                return .json(String(text.prefix(220)))
            }
            return .text(String(text.prefix(220)))
        }

        return .unknownBinary
    }

    private static func looksLikeTransportStream(_ data: Data) -> Bool {
        guard data.count >= 188 * 3 else { return false }
        let syncOffsets = [0, 188, 376]
        return syncOffsets.allSatisfy { offset in data[offset] == 0x47 }
    }

    private static func looksLikeMP4(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let probes = ["ftyp", "moov", "moof", "styp", "mdat"]
        let prefix = data.prefix(256)
        return probes.contains { token in
            prefix.range(of: Data(token.utf8)) != nil
        }
    }
}

private enum FFmpegTransmuxer {
    private static let avErrorEOF = fferrtag(69, 79, 70, 32) // "EOF "

    static func transmuxToTransportStream(sourceURL: URL, outputURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            try transmuxSync(sourceURL: sourceURL, outputURL: outputURL)
        }.value
    }

    private static func transmuxSync(sourceURL: URL, outputURL: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: outputURL)

        var inputContext: UnsafeMutablePointer<AVFormatContext>?
        var outputContext: UnsafeMutablePointer<AVFormatContext>?
        var packet = AVPacket()
        var success = false

        defer {
            av_packet_unref(&packet)

            if let outputContext {
                if let oformat = outputContext.pointee.oformat,
                   (oformat.pointee.flags & AVFMT_NOFILE) == 0,
                   outputContext.pointee.pb != nil {
                    avio_closep(&outputContext.pointee.pb)
                }
                avformat_free_context(outputContext)
            }

            if inputContext != nil {
                avformat_close_input(&inputContext)
            }

            if !success {
                try? fileManager.removeItem(at: outputURL)
            }
        }

        let openStatus = sourceURL.path.withCString { path in
            avformat_open_input(&inputContext, path, nil, nil)
        }
        guard openStatus >= 0, let inputContext else {
            throw ScannerError.serverError("FFmpeg open input failed (\(openStatus))")
        }

        let infoStatus = avformat_find_stream_info(inputContext, nil)
        guard infoStatus >= 0 else {
            throw ScannerError.serverError("FFmpeg read stream info failed (\(infoStatus))")
        }

        let allocStatus = "mpegts".withCString { formatName in
            outputURL.path.withCString { path in
                avformat_alloc_output_context2(&outputContext, nil, formatName, path)
            }
        }
        guard allocStatus >= 0, let outputContext else {
            throw ScannerError.serverError("FFmpeg create output failed (\(allocStatus))")
        }

        let streamCount = Int(inputContext.pointee.nb_streams)
        var streamMapping = Array(repeating: Int32(-1), count: streamCount)

        for index in 0..<streamCount {
            guard let inputStream = stream(at: Int32(index), in: inputContext) else { continue }
            let mediaType = inputStream.pointee.codecpar.pointee.codec_type
            guard mediaType == AVMEDIA_TYPE_VIDEO || mediaType == AVMEDIA_TYPE_AUDIO || mediaType == AVMEDIA_TYPE_SUBTITLE else {
                continue
            }

            guard let outputStream = avformat_new_stream(outputContext, nil) else {
                throw ScannerError.serverError("FFmpeg create output stream failed")
            }

            let copyStatus = avcodec_parameters_copy(outputStream.pointee.codecpar, inputStream.pointee.codecpar)
            guard copyStatus >= 0 else {
                throw ScannerError.serverError("FFmpeg copy codec parameters failed (\(copyStatus))")
            }

            outputStream.pointee.codecpar.pointee.codec_tag = 0
            outputStream.pointee.time_base = inputStream.pointee.time_base
            streamMapping[index] = outputStream.pointee.index
        }

        if let oformat = outputContext.pointee.oformat, (oformat.pointee.flags & AVFMT_NOFILE) == 0 {
            let ioStatus = outputURL.path.withCString { path in
                avio_open(&outputContext.pointee.pb, path, AVIO_FLAG_WRITE)
            }
            guard ioStatus >= 0 else {
                throw ScannerError.serverError("FFmpeg open output failed (\(ioStatus))")
            }
        }

        let headerStatus = avformat_write_header(outputContext, nil)
        guard headerStatus >= 0 else {
            throw ScannerError.serverError("FFmpeg write header failed (\(headerStatus))")
        }

        while true {
            let readStatus = av_read_frame(inputContext, &packet)
            if readStatus < 0 {
                guard readStatus == avErrorEOF else {
                    throw ScannerError.serverError("FFmpeg read packet failed (\(readStatus))")
                }
                break
            }

            defer { av_packet_unref(&packet) }

            guard packet.stream_index >= 0, Int(packet.stream_index) < streamMapping.count else {
                continue
            }
            let mappedStreamIndex = streamMapping[Int(packet.stream_index)]
            guard mappedStreamIndex >= 0 else {
                continue
            }

            guard
                let inputStream = stream(at: packet.stream_index, in: inputContext),
                let outputStream = stream(at: mappedStreamIndex, in: outputContext)
            else {
                throw ScannerError.serverError("FFmpeg stream lookup failed")
            }

            av_packet_rescale_ts(&packet, inputStream.pointee.time_base, outputStream.pointee.time_base)
            packet.stream_index = mappedStreamIndex
            packet.pos = -1

            let writeStatus = av_interleaved_write_frame(outputContext, &packet)
            guard writeStatus >= 0 else {
                throw ScannerError.serverError("FFmpeg write packet failed (\(writeStatus))")
            }
        }

        let trailerStatus = av_write_trailer(outputContext)
        guard trailerStatus >= 0 else {
            throw ScannerError.serverError("FFmpeg write trailer failed (\(trailerStatus))")
        }

        success = true
    }

    private static func stream(
        at index: Int32,
        in context: UnsafeMutablePointer<AVFormatContext>
    ) -> UnsafeMutablePointer<AVStream>? {
        guard index >= 0, index < context.pointee.nb_streams, let streams = context.pointee.streams else {
            return nil
        }
        return streams[Int(index)]
    }

    private static func fferrtag(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int32 {
        let tag = UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
        return -Int32(bitPattern: tag)
    }
}
