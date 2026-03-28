import Foundation

/// SMB scanner — requires AMSMB2 Swift Package for full functionality.
/// For now, implements a basic approach: download video to temp file for playback.
///
/// To add AMSMB2:
/// 1. In Xcode: File → Add Package Dependencies
/// 2. URL: https://github.com/nicklama/AMSMB2
/// 3. Add to KidsTV target
///
/// Until AMSMB2 is added, this scanner shows a helpful error message.
struct SMBScanner: SourceScanner {

    func scan(source: MediaSource) async throws -> [Video] {
        guard let host = source.config.host, !host.isEmpty,
              let share = source.config.share, !share.isEmpty else {
            throw ScannerError.missingConfig("Host and Share are required")
        }

        #if canImport(AMSMB2)
        return try await scanSMB(source: source, host: host, share: share)
        #else
        throw ScannerError.notImplemented("SMB requires the AMSMB2 package.\nAdd it via Xcode → File → Add Package Dependencies\nURL: https://github.com/nicklama/AMSMB2")
        #endif
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        #if canImport(AMSMB2)
        return try await downloadAndPlay(video: video, source: source)
        #else
        throw ScannerError.notImplemented("SMB playback requires AMSMB2 package")
        #endif
    }

    #if canImport(AMSMB2)
    // MARK: - AMSMB2 Implementation

    private func scanSMB(source: MediaSource, host: String, share: String) async throws -> [Video] {
        let videoExts = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts"])
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]

        let serverURL = URL(string: "smb://\(host)")!
        let credential = URLCredential(
            user: source.config.username ?? "guest",
            password: source.config.password ?? "",
            persistence: .forSession
        )
        let smb = AMSMB2(url: serverURL, credential: credential)!
        try await smb.connect()
        try await smb.connectShare(name: share)

        let basePath = source.config.smbPath ?? "/"
        var videos: [Video] = []

        func enumerate(path: String) async throws {
            let items = try await smb.contentsOfDirectory(atPath: path)
            for item in items {
                let name = item[.nameKey] as? String ?? ""
                if name == "." || name == ".." { continue }
                let fullPath = "\(path)/\(name)"
                let isDir = (item[.fileResourceTypeKey] as? URLFileResourceType) == .directory

                if isDir {
                    try await enumerate(path: fullPath)
                } else {
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard videoExts.contains(ext) else { continue }
                    let title = (name as NSString).deletingPathExtension
                    let size = item[.fileSizeKey] as? Int64
                    videos.append(Video(
                        title: title,
                        sourceId: source.id,
                        remotePath: fullPath,
                        duration: 0,
                        resolution: nil,
                        fileSize: size,
                        thumbnailColor: colors.randomElement()!,
                        remoteItemId: fullPath
                    ))
                }
            }
        }
        try await enumerate(path: basePath)
        try await smb.disconnectShare()
        return videos
    }

    private func downloadAndPlay(video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let host = source.config.host, let share = source.config.share else {
            throw ScannerError.missingConfig("Host and Share required")
        }
        let serverURL = URL(string: "smb://\(host)")!
        let credential = URLCredential(
            user: source.config.username ?? "guest",
            password: source.config.password ?? "",
            persistence: .forSession
        )
        let smb = AMSMB2(url: serverURL, credential: credential)!
        try await smb.connect()
        try await smb.connectShare(name: share)

        // Download to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
        let outputStream = OutputStream(url: tempFile, append: false)!
        outputStream.open()
        defer { outputStream.close() }

        _ = try await smb.downloadItem(atPath: video.remotePath, to: outputStream)
        try await smb.disconnectShare()

        return StreamableMedia(url: tempFile, httpHeaders: [:])
    }
    #endif
}
