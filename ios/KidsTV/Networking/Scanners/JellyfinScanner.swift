import Foundation

/// Jellyfin is API-compatible with Emby — delegates to EmbyScanner
struct JellyfinScanner: SourceScanner {

    private let emby = EmbyScanner()

    func scan(source: MediaSource) async throws -> [Video] {
        try await emby.scan(source: source)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        try await emby.streamingURL(for: video, source: source)
    }
}
