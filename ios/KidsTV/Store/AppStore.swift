import Foundation
import Observation
import AVFoundation

@Observable
final class AppStore {

    // MARK: - State

    var sources: [MediaSource] = []
    var videos: [Video] = []
    var channels: [Channel] = []
    var playbackStates: [String: PlaybackState] = [:]   // keyed by channelId
    var watchTimeRecords: [WatchTimeRecord] = []
    var settings: AppSettings = AppSettings()
    var locale: AppLocale = .en
    var isAdminAuthenticated: Bool = false

    // MARK: - Init

    init() {
        load()
        if sources.isEmpty { seedMockData() }
    }

    // MARK: - Locale

    enum AppLocale: String, Codable { case en, zh }

    func setLocale(_ l: AppLocale) {
        locale = l
        save()
    }

    // MARK: - Auth

    func authenticateAdmin(pin: String) -> Bool {
        guard pin == settings.pin else { return false }
        isAdminAuthenticated = true
        return true
    }

    func logoutAdmin() {
        isAdminAuthenticated = false
    }

    // MARK: - Sources

    func addSource(_ source: MediaSource) {
        sources.append(source)
        save()
    }

    func updateSource(_ source: MediaSource) {
        guard let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[i] = source
        save()
    }

    func deleteSource(id: String) {
        let removedVideoIds = Set(videos.filter { $0.sourceId == id }.map(\.id))
        sources.removeAll { $0.id == id }
        videos.removeAll { $0.sourceId == id }
        // Clean up orphaned references in channels
        for i in channels.indices {
            channels[i].videoIds.removeAll { removedVideoIds.contains($0) }
        }
        save()
    }

    @MainActor
    func scanSource(id: String) async {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].scanStatus = .scanning

        let source = sources[i]
        do {
            let found: [Video]
            if source.type == .local {
                found = try await scanLocalSource(source: source)
            } else if let scanner = ScannerRegistry.scanner(for: source.type) {
                found = try await scanner.scan(source: source)
            } else {
                found = []
            }
            // Remove old videos for this source, add new ones
            videos.removeAll { $0.sourceId == id }
            videos.append(contentsOf: found)
            sources[i].scanStatus = .idle
            sources[i].lastScanDate = .now
            sources[i].videoCount = found.count
            sources[i].errorMessage = nil
        } catch {
            sources[i].scanStatus = .error
            sources[i].errorMessage = error.localizedDescription
        }
        save()
    }

    private func scanLocalSource(source: MediaSource) async throws -> [Video] {
        let folderURL: URL

        // Resolve security-scoped bookmark if available
        if let bookmark = source.config.dirBookmark {
            var isStale = false
            folderURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } else if let path = source.config.dirPath {
            folderURL = URL(fileURLWithPath: path)
        } else {
            throw ScanError.noPathConfigured
        }

        let hasScope = folderURL.startAccessingSecurityScopedResource()
        defer { if hasScope { folderURL.stopAccessingSecurityScopedResource() } }

        let videoExtensions = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts", "m2ts"])
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Video] = []
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C","#E67E22","#1A252F"]

        for case let fileURL as URL in enumerator {
            guard videoExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            let asset = AVURLAsset(url: fileURL)
            let duration: TimeInterval
            let resolution: String?

            do {
                let cmDuration = try await asset.load(.duration)
                duration = cmDuration.seconds.isNaN ? 0 : cmDuration.seconds

                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let size = try await track.load(.naturalSize)
                    resolution = "\(Int(size.width))x\(Int(size.height))"
                } else {
                    resolution = nil
                }
            } catch {
                continue
            }

            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = attrs?.fileSize.map { Int64($0) }

            let video = Video(
                title: fileURL.deletingPathExtension().lastPathComponent,
                sourceId: source.id,
                remotePath: fileURL.path,
                duration: duration,
                resolution: resolution,
                fileSize: fileSize,
                thumbnailColor: colors.randomElement()!
            )
            found.append(video)
        }

        return found
    }

    enum ScanError: LocalizedError {
        case noPathConfigured
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .noPathConfigured: return "No folder selected"
            case .accessDenied: return "Access denied — please re-select the folder"
            }
        }
    }

    // MARK: - Videos

    func videos(for sourceId: String) -> [Video] {
        videos.filter { $0.sourceId == sourceId }
    }

    func video(id: String) -> Video? {
        videos.first { $0.id == id }
    }

    // MARK: - Channels

    func addChannel(_ channel: Channel) {
        var ch = channel
        ch.sortOrder = channels.count
        channels.append(ch)
        save()
    }

    func updateChannel(_ channel: Channel) {
        guard let i = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        channels[i] = channel
        save()
    }

    func deleteChannel(id: String) {
        channels.removeAll { $0.id == id }
        playbackStates.removeValue(forKey: id)
        save()
    }

    func reorderChannels(from source: IndexSet, to destination: Int) {
        channels.move(fromOffsets: source, toOffset: destination)
        for (i, _) in channels.enumerated() { channels[i].sortOrder = i }
        save()
    }

    var sortedChannels: [Channel] {
        channels.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Playback

    func savePlaybackState(_ state: PlaybackState) {
        playbackStates[state.channelId] = state
        settings.lastChannelId = state.channelId
        save()
    }

    func playbackState(for channelId: String) -> PlaybackState? {
        playbackStates[channelId]
    }

    // MARK: - Streaming URL Resolution

    func resolvePlaybackURL(for video: Video) async throws -> StreamableMedia {
        guard let source = sources.first(where: { $0.id == video.sourceId }),
              let scanner = ScannerRegistry.scanner(for: source.type) else {
            // Local file fallback
            return StreamableMedia(url: URL(fileURLWithPath: video.remotePath), httpHeaders: [:])
        }
        return try await scanner.streamingURL(for: video, source: source)
    }

    func prefetchPlayback(for video: Video) {
        Task(priority: .background) {
            do {
                _ = try await resolvePlaybackURL(for: video)
                print("[KidsTV] Prefetched playback for \(video.title)")
            } catch {
                print("[KidsTV] Prefetch failed for \(video.title): \(error)")
            }
        }
    }

    // MARK: - Watch Time

    func addWatchTime(seconds: Int) {
        let key = WatchTimeRecord.todayKey
        if let i = watchTimeRecords.firstIndex(where: { $0.date == key }) {
            watchTimeRecords[i].totalSeconds += seconds
        } else {
            watchTimeRecords.append(WatchTimeRecord(date: key, totalSeconds: seconds))
        }
        save()
    }

    var todayWatchSeconds: Int {
        watchTimeRecords.first { $0.date == WatchTimeRecord.todayKey }?.totalSeconds ?? 0
    }

    var isTimeLimitReached: Bool {
        guard let limit = settings.dailyLimitMinutes else { return false }
        return todayWatchSeconds >= limit * 60
    }

    var isWithinAllowedTime: Bool {
        guard let start = settings.allowedStartTime,
              let end = settings.allowedEndTime else { return true }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        guard let s = fmt.date(from: start), let e = fmt.date(from: end) else { return true }
        let now = fmt.date(from: fmt.string(from: .now)) ?? .now
        return now >= s && now <= e
    }

    // MARK: - Settings

    func updateSettings(_ s: AppSettings) {
        settings = s
        save()
    }

    // MARK: - Mock Data

    private func seedMockData() {
        let s1 = MediaSource(id: "s1", name: "Home NAS", type: .smb,
                             config: SourceConfig(host: "192.168.1.10", share: "media"),
                             videoCount: 8)
        let s2 = MediaSource(id: "s2", name: "Aliyun Drive", type: .aliyunDrive,
                             config: SourceConfig(), videoCount: 7)
        let s3 = MediaSource(id: "s3", name: "Emby Server", type: .emby,
                             config: SourceConfig(serverUrl: "http://192.168.1.20:8096"),
                             scanStatus: .error, videoCount: 5,
                             errorMessage: "Connection refused")
        sources = [s1, s2, s3]

        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]
        videos = (1...20).map { i in
            Video(id: "v\(i)", title: "Video \(i)",
                  sourceId: i <= 8 ? "s1" : (i <= 15 ? "s2" : "s3"),
                  remotePath: "/media/video\(i).mp4",
                  duration: Double.random(in: 300...3600),
                  resolution: ["1280x720","1920x1080","3840x2160"].randomElement(),
                  fileSize: Int64.random(in: 100_000_000...2_000_000_000),
                  thumbnailColor: colors.randomElement()!)
        }

        channels = [
            Channel(id: "c1", name: "Cartoons", iconName: "sparkles",
                    iconColor: "#E74C3C", defaultVolume: 0.8, sortOrder: 0,
                    videoIds: Array(videos.prefix(5).map(\.id))),
            Channel(id: "c2", name: "Nature", iconName: "leaf",
                    iconColor: "#2ECC71", defaultVolume: 0.7, sortOrder: 1,
                    videoIds: Array(videos.dropFirst(5).prefix(5).map(\.id))),
            Channel(id: "c3", name: "Science", iconName: "atom",
                    iconColor: "#3498DB", defaultVolume: 0.75, sortOrder: 2,
                    videoIds: Array(videos.dropFirst(10).prefix(5).map(\.id))),
            Channel(id: "c4", name: "Music", iconName: "music.note",
                    iconColor: "#9B59B6", defaultVolume: 0.9, sortOrder: 3,
                    videoIds: Array(videos.dropFirst(15).map(\.id))),
        ]

        save()
    }
}
