import Foundation

/// Represents a playable media item with optional auth headers
struct StreamSegment {
    let url: URL
    let duration: Double
}

struct StreamableMedia {
    let url: URL
    let httpHeaders: [String: String]
    let segments: [StreamSegment]?

    init(url: URL, httpHeaders: [String: String], segments: [StreamSegment]? = nil) {
        self.url = url
        self.httpHeaders = httpHeaders
        self.segments = segments
    }
}

/// Protocol for scanning remote media sources and resolving streaming URLs
protocol SourceScanner {
    /// Scan the source for video files, returning metadata for each
    func scan(source: MediaSource) async throws -> [Video]

    /// Resolve a video to a playable URL (may regenerate expiring tokens/URLs)
    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia
}
