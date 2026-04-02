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
        checkError(mpv_stream_cb_add_ro(mpv, "kidstv", nil, kidsTVSessionOpen))

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

final class BaiduMPVSegmentDescriptor {
    let index: Int
    let url: URL
    let localFileURL: URL
    let duration: Double

    init(index: Int, url: URL, localFileURL: URL, duration: Double) {
        self.index = index
        self.url = url
        self.localFileURL = localFileURL
        self.duration = duration
    }
}

final class BaiduMPVStreamRegistry {
    static let shared = BaiduMPVStreamRegistry()

    private let lock = NSLock()
    private var sessions: [String: BaiduMPVStreamSession] = [:]

    func registerSession(cacheKey: String, segments: [BaiduMPVSegmentDescriptor]) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[cacheKey] {
            existing.update(segments: segments)
        } else {
            sessions[cacheKey] = BaiduMPVStreamSession(cacheKey: cacheKey, segments: segments)
        }
    }

    func markSegmentReady(cacheKey: String, index: Int, byteCount: Int) {
        lock.lock()
        let session = sessions[cacheKey]
        lock.unlock()
        session?.markSegmentReady(index: index, byteCount: byteCount)
    }

    func markSegmentEvicted(cacheKey: String, index: Int) {
        lock.lock()
        let session = sessions[cacheKey]
        lock.unlock()
        session?.markSegmentEvicted(index: index)
    }

    func markSessionFinished(cacheKey: String) {
        lock.lock()
        let session = sessions[cacheKey]
        lock.unlock()
        session?.markFinished()
    }

    func markSessionFailed(cacheKey: String, message: String) {
        lock.lock()
        let session = sessions[cacheKey]
        lock.unlock()
        session?.markFailed(message: message)
    }

    func makeSessionStream(for uri: String) -> BaiduMPVSessionStream? {
        guard let cacheKey = parseSession(uri: uri) else { return nil }
        lock.lock()
        let session = sessions[cacheKey]
        lock.unlock()
        return session?.makeSessionStream()
    }

    func removeSession(cacheKey: String) {
        lock.lock()
        sessions.removeValue(forKey: cacheKey)
        lock.unlock()
    }

    private func parseSession(uri: String) -> String? {
        guard let components = URLComponents(string: uri), components.scheme == "kidstv" else { return nil }
        let parts = components.path
            .split(separator: "/")
            .map(String.init)
        guard components.host == "session", let sessionId = parts.first, !sessionId.isEmpty else {
            return nil
        }
        return sessionId
    }
}

final class BaiduMPVStreamSession {
    let cacheKey: String
    private let condition = NSCondition()
    private var segments: [BaiduMPVSegmentDescriptor]
    private var readySegments: Set<Int> = []
    private var segmentSizes: [Int: Int] = [:]
    private var contiguousReadyByteCount: Int64 = 0
    private var contiguousReadyIndex: Int = 0
    private var evictedThroughIndex: Int = -1
    private var finished = false
    private var failedMessage: String?

    init(cacheKey: String, segments: [BaiduMPVSegmentDescriptor]) {
        self.cacheKey = cacheKey
        self.segments = segments
    }

    func update(segments: [BaiduMPVSegmentDescriptor]) {
        condition.lock()
        self.segments = segments
        readySegments = Set(segments.compactMap { FileManager.default.fileExists(atPath: $0.localFileURL.path) ? $0.index : nil })
        segmentSizes.removeAll()
        for index in readySegments {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: segments[index].localFileURL.path),
               let size = (attrs[.size] as? NSNumber)?.intValue,
               size > 0 {
                segmentSizes[index] = size
            }
        }
        contiguousReadyByteCount = 0
        contiguousReadyIndex = 0
        evictedThroughIndex = -1
        advanceContiguousReady()
        failedMessage = nil
        finished = false
        condition.broadcast()
        condition.unlock()
    }

    func markSegmentReady(index: Int, byteCount: Int) {
        condition.lock()
        readySegments.insert(index)
        segmentSizes[index] = byteCount
        advanceContiguousReady()
        condition.broadcast()
        condition.unlock()
    }

    func markSegmentEvicted(index: Int) {
        condition.lock()
        evictedThroughIndex = max(evictedThroughIndex, index)
        condition.broadcast()
        condition.unlock()
    }

    func markFinished() {
        condition.lock()
        finished = true
        condition.broadcast()
        condition.unlock()
    }

    func markFailed(message: String) {
        condition.lock()
        failedMessage = message
        condition.broadcast()
        condition.unlock()
    }

    func makeSessionStream() -> BaiduMPVSessionStream {
        BaiduMPVSessionStream(session: self, cacheKey: cacheKey)
    }

    func waitReadableBytes(from offset: Int64, cancelled: @escaping () -> Bool) throws -> Int {
        condition.lock()
        defer { condition.unlock() }

        while true {
            if cancelled() {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_GENERIC.rawValue), userInfo: [NSLocalizedDescriptionKey: "Cancelled"])
            }
            if offset < contiguousReadyByteCount {
                return Int(contiguousReadyByteCount - offset)
            }

            if finished {
                return 0
            }

            if let message = failedMessage {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_LOADING_FAILED.rawValue), userInfo: [NSLocalizedDescriptionKey: message])
            }

            condition.wait(until: Date().addingTimeInterval(0.25))
        }
    }

    func segmentDescriptor(at index: Int) -> BaiduMPVSegmentDescriptor? {
        condition.lock()
        defer { condition.unlock() }
        guard segments.indices.contains(index) else { return nil }
        return segments[index]
    }

    func segmentCount() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return segments.count
    }

    func totalSizeIfFinished() -> Int64? {
        condition.lock()
        defer { condition.unlock() }
        guard finished else { return nil }
        return contiguousReadyByteCount
    }

    func canSeek(to offset: Int64) -> Bool {
        locateBuffered(offset: offset) != nil
    }

    func prefetchIndex(for offset: Int64) -> Int {
        if let location = locateBuffered(offset: offset) {
            return location.index
        }
        condition.lock()
        defer { condition.unlock() }
        guard offset > 0 else { return 0 }

        var remaining = offset
        for index in segments.indices {
            guard let size = segmentSizes[index], size > 0 else {
                return min(index, max(segments.count - 1, 0))
            }
            let size64 = Int64(size)
            if remaining < size64 {
                return index
            }
            remaining -= size64
        }
        return max(segments.count - 1, 0)
    }

    func waitUntilSegmentReady(index: Int, cancelled: @escaping () -> Bool) throws {
        condition.lock()
        defer { condition.unlock() }

        while true {
            if cancelled() {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_GENERIC.rawValue), userInfo: [NSLocalizedDescriptionKey: "Cancelled"])
            }
            if readySegments.contains(index) {
                return
            }
            if finished {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_LOADING_FAILED.rawValue), userInfo: [NSLocalizedDescriptionKey: "Segment unavailable after download completed"])
            }
            if index <= evictedThroughIndex {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_UNSUPPORTED.rawValue), userInfo: [NSLocalizedDescriptionKey: "Requested segment has been evicted"])
            }
            if let message = failedMessage {
                throw NSError(domain: "KidsTV.Stream", code: Int(MPV_ERROR_LOADING_FAILED.rawValue), userInfo: [NSLocalizedDescriptionKey: message])
            }
            condition.wait(until: Date().addingTimeInterval(0.25))
        }
    }

    func locateBuffered(offset: Int64) -> (index: Int, inSegmentOffset: Int)? {
        condition.lock()
        defer { condition.unlock() }
        guard offset >= retainedStartOffsetLocked(), offset >= 0 else { return nil }

        var remaining = offset
        for index in segments.indices {
            guard let size = segmentSizes[index], size > 0 else { return nil }
            let size64 = Int64(size)
            if remaining < size64 {
                guard index > evictedThroughIndex, readySegments.contains(index) else { return nil }
                return (index, Int(remaining))
            }
            remaining -= size64
        }

        if finished, offset == contiguousReadyByteCount, let lastIndex = segments.indices.last, let lastSize = segmentSizes[lastIndex] {
            return (lastIndex, lastSize)
        }
        return nil
    }

    private func advanceContiguousReady() {
        while let size = segmentSizes[contiguousReadyIndex], size > 0 {
            contiguousReadyByteCount += Int64(size)
            contiguousReadyIndex += 1
        }
    }

    private func retainedStartOffsetLocked() -> Int64 {
        guard evictedThroughIndex >= 0 else { return 0 }
        var total: Int64 = 0
        for index in 0...evictedThroughIndex {
            guard let size = segmentSizes[index] else { break }
            total += Int64(size)
        }
        return total
    }
}

final class BaiduMPVSessionStream {
    private let session: BaiduMPVStreamSession
    private let cacheKey: String
    private let lock = NSLock()
    private var absoluteOffset: Int64 = 0
    private var currentSegmentIndex = 0
    private var currentSegmentOffset = 0
    private var currentHandle: FileHandle?
    private var cancelled = false

    init(session: BaiduMPVStreamSession, cacheKey: String) {
        self.session = session
        self.cacheKey = cacheKey
        requestPrefetch(for: 0)
    }

    func read(into buffer: UnsafeMutablePointer<CChar>, maxBytes: UInt64) -> Int64 {
        guard maxBytes > 0 else { return 0 }
        do {
            var totalRead = 0
            while totalRead < Int(maxBytes) {
                let location = try ensureReadableLocation()
                let descriptor = session.segmentDescriptor(at: location.index)
                guard let descriptor else { break }

                let size = try sizeOfSegment(descriptor.localFileURL)
                let available = max(0, size - location.inSegmentOffset)
                if available == 0 {
                    if !advanceToNextSegment() {
                        break
                    }
                    continue
                }

                let chunk = min(Int(maxBytes) - totalRead, available)
                let data = try readSegmentChunk(
                    fileURL: descriptor.localFileURL,
                    segmentIndex: location.index,
                    offset: location.inSegmentOffset,
                    count: chunk
                )
                guard !data.isEmpty else {
                    if !advanceToNextSegment() {
                        break
                    }
                    continue
                }

                data.copyBytes(
                    to: UnsafeMutableRawBufferPointer(start: buffer.advanced(by: totalRead), count: data.count),
                    count: data.count
                )
                totalRead += data.count
                absoluteOffset += Int64(data.count)
                currentSegmentIndex = location.index
                currentSegmentOffset = location.inSegmentOffset + data.count
                requestPrefetch(for: session.prefetchIndex(for: absoluteOffset))
            }
            return Int64(totalRead)
        } catch {
            return -1
        }
    }

    func seek(to newOffset: Int64) -> Int64 {
        guard newOffset >= 0 else { return Int64(MPV_ERROR_GENERIC.rawValue) }
        guard let location = session.locateBuffered(offset: newOffset), session.canSeek(to: newOffset) else {
            return Int64(MPV_ERROR_UNSUPPORTED.rawValue)
        }
        lock.lock()
        absoluteOffset = newOffset
        currentSegmentIndex = location.index
        currentSegmentOffset = location.inSegmentOffset
        try? currentHandle?.close()
        currentHandle = nil
        lock.unlock()
        requestPrefetch(for: location.index)
        return newOffset
    }

    func size() -> Int64 {
        session.totalSizeIfFinished() ?? Int64(MPV_ERROR_UNSUPPORTED.rawValue)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        absoluteOffset = 0
        cancelled = true
        try? currentHandle?.close()
        currentHandle = nil
        lock.unlock()
        Task {
            await BaiduPlaybackPipeline.shared.closeSession(cacheKey: cacheKey)
            BaiduMPVStreamRegistry.shared.removeSession(cacheKey: cacheKey)
        }
    }

    private func ensureReadableLocation() throws -> (index: Int, inSegmentOffset: Int) {
        while true {
            if let location = session.locateBuffered(offset: absoluteOffset) {
                try session.waitUntilSegmentReady(index: location.index) { [weak self] in
                    self?.lock.lock()
                    let isCancelled = self?.cancelled ?? true
                    self?.lock.unlock()
                    return isCancelled
                }
                return location
            }

            let available = try session.waitReadableBytes(from: absoluteOffset) { [weak self] in
                self?.lock.lock()
                let isCancelled = self?.cancelled ?? true
                self?.lock.unlock()
                return isCancelled
            }
            if available == 0 {
                return (currentSegmentIndex, currentSegmentOffset)
            }
        }
    }

    private func readSegmentChunk(fileURL: URL, segmentIndex: Int, offset: Int, count: Int) throws -> Data {
        lock.lock()
        let handle = currentHandle
        lock.unlock()

        let segmentHandle: FileHandle
        if let handle, currentSegmentIndex == segmentIndex {
            segmentHandle = handle
        } else {
            try? handle?.close()
            segmentHandle = try FileHandle(forReadingFrom: fileURL)
            lock.lock()
            currentHandle = segmentHandle
            lock.unlock()
        }

        try segmentHandle.seek(toOffset: UInt64(max(0, offset)))
        return try segmentHandle.read(upToCount: count) ?? Data()
    }

    private func advanceToNextSegment() -> Bool {
        lock.lock()
        currentSegmentIndex += 1
        currentSegmentOffset = 0
        try? currentHandle?.close()
        currentHandle = nil
        let nextIndex = currentSegmentIndex
        lock.unlock()
        requestPrefetch(for: nextIndex)
        return nextIndex < session.segmentCount()
    }

    private func sizeOfSegment(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
    }

    private func requestPrefetch(for index: Int) {
        guard index >= 0 else { return }
        Task {
            await BaiduPlaybackPipeline.shared.requestRollingPrefetch(cacheKey: cacheKey, currentIndex: index)
        }
    }

}

private func releaseCookie<T: AnyObject>(_ type: T.Type, _ cookie: UnsafeMutableRawPointer?) -> T? {
    guard let cookie else { return nil }
    return Unmanaged<T>.fromOpaque(cookie).takeRetainedValue()
}

private func withCookie<T: AnyObject, R>(_ type: T.Type, _ cookie: UnsafeMutableRawPointer?, _ body: (T) -> R) -> R? {
    guard let cookie else { return nil }
    let value = Unmanaged<T>.fromOpaque(cookie).takeUnretainedValue()
    return body(value)
}

private let kidsTVSessionOpen: mpv_stream_cb_open_ro_fn = { _, uri, info in
    guard
        let uri,
        let info,
        let stream = BaiduMPVStreamRegistry.shared.makeSessionStream(for: String(cString: uri))
    else {
        return Int32(MPV_ERROR_LOADING_FAILED.rawValue)
    }
    info.pointee.cookie = Unmanaged.passRetained(stream).toOpaque()
    info.pointee.read_fn = kidsTVSessionRead
    info.pointee.seek_fn = kidsTVSessionSeek
    info.pointee.size_fn = kidsTVSessionSize
    info.pointee.close_fn = kidsTVSessionClose
    info.pointee.cancel_fn = kidsTVSessionCancel
    return 0
}

private let kidsTVSessionRead: mpv_stream_cb_read_fn = { cookie, buf, nbytes in
    withCookie(BaiduMPVSessionStream.self, cookie) { $0.read(into: buf!, maxBytes: nbytes) } ?? -1
}

private let kidsTVSessionSeek: mpv_stream_cb_seek_fn = { cookie, offset in
    withCookie(BaiduMPVSessionStream.self, cookie) { $0.seek(to: offset) } ?? Int64(MPV_ERROR_GENERIC.rawValue)
}

private let kidsTVSessionSize: mpv_stream_cb_size_fn = { cookie in
    withCookie(BaiduMPVSessionStream.self, cookie) { $0.size() } ?? Int64(MPV_ERROR_UNSUPPORTED.rawValue)
}

private let kidsTVSessionClose: mpv_stream_cb_close_fn = { cookie in
    if let stream = releaseCookie(BaiduMPVSessionStream.self, cookie) {
        stream.close()
    }
}

private let kidsTVSessionCancel: mpv_stream_cb_cancel_fn = { cookie in
    _ = withCookie(BaiduMPVSessionStream.self, cookie) { $0.cancel() }
}
