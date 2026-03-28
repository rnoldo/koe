import SwiftUI
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    let video: Video
    let volume: Double
    var streamURL: URL?             // resolved streaming URL (overrides remotePath)
    var streamHeaders: [String: String]?  // auth headers for remote playback
    @Binding var currentTime: TimeInterval
    @Binding var isPlaying: Bool
    let onFinished: () -> Void

    func makeUIView(context: Context) -> PlayerUIView {
        print("[KidsTV] makeUIView for video: \(video.title) id: \(video.id)")
        let view = PlayerUIView()
        view.onFinished = onFinished
        view.onTimeUpdate = { t in currentTime = t }
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.currentVideoId != video.id {
            print("[KidsTV] updateUIView: configuring new video \(video.title)")
            uiView.httpHeaders = streamHeaders
            uiView.configure(with: video, volume: volume, startTime: currentTime, overrideURL: streamURL)
        }
        uiView.setPlaying(isPlaying)
        uiView.setVolume(volume)
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        print("[KidsTV] dismantleUIView")
        uiView.teardown()
    }
}

final class PlayerUIView: UIView {
    var onFinished: (() -> Void)?
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var httpHeaders: [String: String]?
    private(set) var currentVideoId: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var debugLabel: UILabel?

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var avPlayerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(with video: Video, volume: Double, startTime: TimeInterval, overrideURL: URL? = nil) {
        teardown()
        currentVideoId = video.id
        backgroundColor = UIColor(Color(hex: video.thumbnailColor))
        avPlayerLayer.videoGravity = .resizeAspect
        showDebug("Loading: \(video.title)")

        let url: URL
        let isRemote: Bool
        if let override = overrideURL {
            url = override
            isRemote = url.scheme == "http" || url.scheme == "https"
        } else if video.remotePath.hasPrefix("http://") || video.remotePath.hasPrefix("https://") {
            guard let u = URL(string: video.remotePath) else {
                showDebug("ERROR: Invalid URL\n\(video.remotePath)")
                return
            }
            url = u
            isRemote = true
        } else {
            url = URL(fileURLWithPath: video.remotePath)
            isRemote = false
        }

        if !isRemote {
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[KidsTV] File path: \(url.path)")
            print("[KidsTV] File exists: \(exists)")
            guard exists else {
                showDebug("FILE NOT FOUND:\n\(url.path)")
                return
            }
        } else {
            print("[KidsTV] Remote URL: \(url.absoluteString)")
        }

        // Use AVURLAsset to support auth headers for remote sources
        let asset: AVURLAsset
        if let headers = httpHeaders, !headers.isEmpty {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.volume = Float(volume)

        if startTime > 0 {
            p.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }

        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    print("[KidsTV] ✅ Ready to play")
                    self?.showDebug("Playing: \(video.title)")
                    // Hide debug after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.debugLabel?.isHidden = true
                    }
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Unknown error"
                    print("[KidsTV] ❌ Failed: \(msg)")
                    self?.showDebug("PLAYBACK ERROR:\n\(msg)")
                case .unknown:
                    print("[KidsTV] ⏳ Status: unknown (loading...)")
                @unknown default:
                    break
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
        p.play()
        print("[KidsTV] Called play()")
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

    private func showDebug(_ message: String) {
        if debugLabel == nil {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .yellow
            label.font = .boldSystemFont(ofSize: 16)
            label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(label)
            debugLabel = label
        }
        debugLabel?.text = message
        debugLabel?.isHidden = false
        debugLabel?.frame = CGRect(x: 20, y: 20, width: bounds.width - 40, height: 120)
    }
}
