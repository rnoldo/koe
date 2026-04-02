import Foundation

struct PlaybackSource {
    let url: URL?
    let headers: [String: String]
    let requiresResolvedStream: Bool
    let signature: String

    var isPendingResolution: Bool {
        requiresResolvedStream && url == nil
    }

    var resolvedURL: URL? {
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
