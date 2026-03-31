import Foundation
import Libmpv
import SwiftUI
import UIKit

private enum MPVProperty {
    static let pause = "pause"
    static let volume = "volume"
    static let timePos = "time-pos"
    static let pausedForCache = "paused-for-cache"
    static let idleActive = "idle-active"
}

final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}

final class MPVPlayerUIView: UIView, PlaybackBackendView {
    var onFinished: (() -> Void)?
    var onTimeUpdate: ((TimeInterval) -> Void)?
    private(set) var currentVideoId: String?
    private(set) var currentStreamSignature: String?

    override class var layerClass: AnyClass { MPVMetalLayer.self }

    private var metalLayer: MPVMetalLayer { layer as! MPVMetalLayer }
    private var mpv: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "KidsTV.mpv.events", qos: .userInitiated)
    private var pendingStartTime: TimeInterval = 0
    private var finishReported = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
    }

    func configure(
        with video: Video,
        source: PlaybackSource,
        volume: Double,
        startTime: TimeInterval
    ) {
        teardown()
        currentVideoId = video.id
        currentStreamSignature = source.signature
        backgroundColor = UIColor(Color(hex: video.thumbnailColor))

        if source.isPendingResolution {
            NSLog("%@", "[KidsTV][MPV] Waiting for resolved stream: \(video.title)")
            return
        }

        guard setupMPV(headers: source.headers) else {
            NSLog("%@", "[KidsTV][MPV] Failed to initialize mpv")
            return
        }

        guard let url = source.resolvedURL ?? resolvedURL(for: video) else {
            NSLog("%@", "[KidsTV][MPV] Missing URL for \(video.title)")
            return
        }
        pendingStartTime = startTime
        let loadTarget = url.isFileURL ? url.path : url.absoluteString
        command("loadfile", args: [loadTarget, "replace"])
        NSLog("%@", "[KidsTV][MPV] Loading single: \(video.title) url: \(loadTarget.prefix(120))")

        setVolume(volume)
        setPlaying(true)
    }

    func setPlaying(_ playing: Bool) {
        setFlag(MPVProperty.pause, !playing)
    }

    func setVolume(_ volume: Double) {
        guard let mpv else { return }
        var value = volume * 100
        mpv_set_property(mpv, MPVProperty.volume, MPV_FORMAT_DOUBLE, &value)
    }

    func teardown() {
        finishReported = false
        pendingStartTime = 0
        currentVideoId = nil
        currentStreamSignature = nil

        NotificationCenter.default.removeObserver(self)

        if let mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
            mpv_terminate_destroy(mpv)
        }
        self.mpv = nil
    }

    @objc private func enterBackground() {
        setPlaying(false)
        checkError(mpv_set_option_string(mpv, "vid", "no"))
    }

    @objc private func enterForeground() {
        checkError(mpv_set_option_string(mpv, "vid", "auto"))
        setPlaying(true)
    }

    private func setupMPV(headers: [String: String]) -> Bool {
        let mpv = mpv_create()
        guard let mpv else { return false }
        self.mpv = mpv

#if DEBUG
        checkError(mpv_request_log_messages(mpv, "info"))
#else
        checkError(mpv_request_log_messages(mpv, "no"))
#endif

        var layerRef = metalLayer
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerRef))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
#if targetEnvironment(simulator)
        checkError(mpv_set_option_string(mpv, "hwdec", "no"))
#else
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
#endif
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(mpv, "keep-open", "no"))
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "demuxer-readahead-secs", "20"))
        checkError(mpv_set_option_string(mpv, "cache-secs", "20"))

        if let userAgent = headers.first(where: { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame })?.value {
            checkError(mpv_set_option_string(mpv, "user-agent", userAgent))
        }
        let extraHeaders = headers
            .filter { $0.key.caseInsensitiveCompare("User-Agent") != .orderedSame }
            .map { "\($0.key): \($0.value)" }
        if !extraHeaders.isEmpty {
            checkError(mpv_set_option_string(mpv, "http-header-fields", extraHeaders.joined(separator: ",")))
        }

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.idleActive, MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            let player = Unmanaged<MPVPlayerUIView>.fromOpaque(context).takeUnretainedValue()
            player.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        return true
    }

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            while let mpv = self.mpv {
                guard let event = mpv_wait_event(mpv, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE {
                    break
                }

                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event: event)
                case MPV_EVENT_FILE_LOADED, MPV_EVENT_PLAYBACK_RESTART:
                    self.handlePlaybackStartIfNeeded()
                case MPV_EVENT_END_FILE:
                    self.handleEndFileEvent(event: event)
                case MPV_EVENT_SHUTDOWN:
                    self.mpv = nil
                    break
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        NSLog("%@", "[KidsTV][MPV][\(String(cString: msg.pointee.prefix))] \(String(cString: msg.pointee.text))")
                    }
                default:
                    break
                }
            }
        }
    }

    private func handlePropertyChange(event: UnsafePointer<mpv_event>) {
        guard let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data))?.pointee else {
            return
        }
        let name = String(cString: property.name)

        switch name {
        case MPVProperty.timePos:
            guard let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onTimeUpdate?(value)
            }
        case MPVProperty.pausedForCache:
            let buffering = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? false
            NSLog("%@", "[KidsTV][MPV] Buffering=\(buffering)")
        case MPVProperty.idleActive:
            let idle = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee ?? false
            if idle, !finishReported {
                finishReported = true
                DispatchQueue.main.async { [weak self] in
                    self?.onFinished?()
                }
            }
        default:
            break
        }
    }

    private func handlePlaybackStartIfNeeded() {
        guard pendingStartTime > 0.05 else { return }
        let offset = pendingStartTime
        pendingStartTime = 0
        command("seek", args: ["\(offset)", "absolute+exact"])
    }

    private func handleEndFileEvent(event: UnsafePointer<mpv_event>) {
        guard let endFile = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data))?.pointee else {
            return
        }
        if endFile.reason == MPV_END_FILE_REASON_ERROR {
            NSLog("%@", "[KidsTV][MPV] End-file error code=\(endFile.error)")
        }
    }

    private func command(_ command: String, args: [String?] = []) {
        guard let mpv else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        checkError(mpv_command(mpv, &cargs))
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        var values = args
        values.insert(command, at: 0)
        values.append(nil)
        return values
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func checkError(_ status: Int32) {
        if status < 0 {
            NSLog("%@", "[KidsTV][MPV] API error: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func resolvedURL(for video: Video) -> URL? {
        if video.remotePath.hasPrefix("http://") || video.remotePath.hasPrefix("https://") {
            return URL(string: video.remotePath)
        }
        return URL(fileURLWithPath: video.remotePath)
    }
}
