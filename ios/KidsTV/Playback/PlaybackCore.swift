import Foundation

struct PlaybackSource {
    let url: URL?
    let headers: [String: String]
    let segments: [StreamSegment]?
    let requiresResolvedStream: Bool
    let signature: String

    var isPendingResolution: Bool {
        requiresResolvedStream && url == nil && (segments?.isEmpty ?? true)
    }

    var resolvedURL: URL? {
        if let segments, let first = segments.first {
            return first.url
        }
        return url
    }
}

protocol PlaybackBackendView: AnyObject {
    var onFinished: (() -> Void)? { get set }
    var onTimeUpdate: ((TimeInterval) -> Void)? { get set }
    var currentVideoId: String? { get }
    var currentStreamSignature: String? { get }

    func configure(
        with video: Video,
        source: PlaybackSource,
        volume: Double,
        startTime: TimeInterval
    )

    func setPlaying(_ playing: Bool)
    func setVolume(_ volume: Double)
    func teardown()
}
