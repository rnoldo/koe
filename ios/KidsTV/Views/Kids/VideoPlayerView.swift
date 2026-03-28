import SwiftUI
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    let video: Video
    let volume: Double
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    let onFinished: () -> Void

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.onFinished = onFinished
        view.onTimeUpdate = { t in currentTime = t }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Only reconfigure if the video changed
        if uiView.currentVideoId != video.id {
            uiView.configure(with: video, volume: volume, startTime: currentTime)
        }
        uiView.setPlaying(isPlaying)
        uiView.setVolume(volume)
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class PlayerUIView: UIView {
    var onFinished: (() -> Void)?
    var onTimeUpdate: ((TimeInterval) -> Void)?
    private(set) var currentVideoId: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var errorLabel: UILabel?

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var avPlayerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        avPlayerLayer.frame = bounds
        errorLabel?.frame = bounds
    }

    func configure(with video: Video, volume: Double, startTime: TimeInterval) {
        teardown()
        currentVideoId = video.id
        backgroundColor = UIColor(Color(hex: video.thumbnailColor))
        avPlayerLayer.videoGravity = .resizeAspect
        hideError()

        let url: URL
        if video.remotePath.hasPrefix("http://") || video.remotePath.hasPrefix("https://") {
            guard let u = URL(string: video.remotePath) else {
                showError("Invalid URL: \(video.remotePath)")
                return
            }
            url = u
        } else {
            url = URL(fileURLWithPath: video.remotePath)
        }

        // Verify file exists before handing to AVPlayer
        if !url.isFileURL || FileManager.default.fileExists(atPath: url.path) == false && url.isFileURL {
            showError("File not found:\n\(url.path)")
            return
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = Float(volume)

        if startTime > 0 {
            p.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }

        // Observe for load errors
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.status == .failed {
                    let msg = item.error?.localizedDescription ?? "Unknown error"
                    self?.showError(msg)
                    print("[KidsTV] AVPlayerItem failed: \(msg)")
                }
            }
        }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard !time.seconds.isNaN else { return }
            self?.onTimeUpdate?(time.seconds)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        avPlayerLayer.player = p
        player = p
    }

    func setPlaying(_ playing: Bool) {
        guard player != nil else { return }
        playing ? player?.play() : player?.pause()
    }

    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func teardown() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
        avPlayerLayer.player = nil
        NotificationCenter.default.removeObserver(self)
        currentVideoId = nil
    }

    @objc private func playerDidFinish() {
        DispatchQueue.main.async { self.onFinished?() }
    }

    private func showError(_ message: String) {
        if errorLabel == nil {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .white
            label.font = .systemFont(ofSize: 13)
            label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            addSubview(label)
            errorLabel = label
        }
        errorLabel?.text = "⚠️ \(message)"
        errorLabel?.isHidden = false
        setNeedsLayout()
    }

    private func hideError() {
        errorLabel?.isHidden = true
    }
}
