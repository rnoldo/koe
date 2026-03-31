import SwiftUI

struct VideoPlayerView: UIViewRepresentable {
    let video: Video
    let volume: Double
    var streamURL: URL?
    var streamHeaders: [String: String]?
    var streamSegments: [StreamSegment]?
    var requiresResolvedStream: Bool = false
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    let onFinished: () -> Void

    private var playbackSource: PlaybackSource {
        PlaybackSource(
            url: streamURL,
            headers: streamHeaders ?? [:],
            segments: streamSegments,
            requiresResolvedStream: requiresResolvedStream,
            signature: streamSignature()
        )
    }

    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.onFinished = onFinished
        view.onTimeUpdate = { t in currentTime = t }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        uiView.configure(
            with: video,
            source: playbackSource,
            volume: volume,
            startTime: currentTime
        )
        uiView.setPlaying(isPlaying)
        uiView.setVolume(volume)
    }

    static func dismantleUIView(_ uiView: PlayerContainerUIView, coordinator: ()) {
        uiView.teardown()
    }

    private func streamSignature() -> String {
        if let segments = streamSegments, !segments.isEmpty {
            let joined = segments.prefix(4).map { $0.url.absoluteString }.joined(separator: "|")
            return "segments:\(segments.count):\(joined)"
        }
        if let streamURL {
            return "url:\(streamURL.absoluteString)"
        }
        return requiresResolvedStream ? "pending" : "fallback"
    }
}

final class PlayerContainerUIView: UIView {
    var onFinished: (() -> Void)? {
        didSet { mpvBackendView.onFinished = onFinished }
    }

    var onTimeUpdate: ((TimeInterval) -> Void)? {
        didSet { mpvBackendView.onTimeUpdate = onTimeUpdate }
    }

    private let mpvBackendView: MPVPlayerUIView = {
        let view = MPVPlayerUIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(mpvBackendView)
        NSLayoutConstraint.activate([
            mpvBackendView.topAnchor.constraint(equalTo: topAnchor),
            mpvBackendView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mpvBackendView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mpvBackendView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        with video: Video,
        source: PlaybackSource,
        volume: Double,
        startTime: TimeInterval
    ) {
        if mpvBackendView.currentVideoId != video.id || mpvBackendView.currentStreamSignature != source.signature {
            mpvBackendView.configure(
                with: video,
                source: source,
                volume: volume,
                startTime: startTime
            )
        }
    }

    func setPlaying(_ playing: Bool) {
        mpvBackendView.setPlaying(playing)
    }

    func setVolume(_ volume: Double) {
        mpvBackendView.setVolume(volume)
    }

    func teardown() {
        mpvBackendView.teardown()
    }
}
