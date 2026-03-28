import SwiftUI

struct KidsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // Navigation state
    @State private var channelIndex = 0
    @State private var videoIndex = 0

    // Playback state
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0

    // UI state
    @State private var showHUD = false
    @State private var showVideoList = false
    @State private var isLocked = false
    @State private var showPauseIcon = false
    @State private var showChannelSwitch = false

    // Watch time timer
    @State private var watchTimer: Timer?

    private var channels: [Channel] { store.sortedChannels }

    private var currentChannel: Channel? {
        guard channelIndex < channels.count else { return nil }
        return channels[channelIndex]
    }

    private var currentVideos: [Video] {
        guard let ch = currentChannel else { return [] }
        return ch.videoIds.compactMap { store.video(id: $0) }
    }

    private var currentVideo: Video? {
        guard videoIndex < currentVideos.count else { return nil }
        return currentVideos[videoIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if channels.isEmpty {
                emptyState
            } else if let video = currentVideo, let channel = currentChannel {
                // Video player layer
                VideoPlayerView(
                    video: video,
                    volume: min(channel.defaultVolume, store.settings.maxVolume),
                    currentTime: $currentTime,
                    isPlaying: $isPlaying
                ) {
                    advanceVideo()
                }

                // Gesture capture layer
                gestureOverlay

                // Progress bar
                VStack {
                    Spacer()
                    progressBar
                }

                // HUD
                if showHUD {
                    VStack {
                        Spacer()
                        ChannelHUDView(
                            channel: channel,
                            channelIndex: channelIndex,
                            totalChannels: channels.count,
                            videoTitle: video.title
                        )
                        .padding(.bottom, 60)
                    }
                    .transition(.opacity)
                }

                // Channel switch overlay
                if showChannelSwitch, let ch = currentChannel {
                    channelSwitchOverlay(channel: ch)
                }

                // Pause icon
                if showPauseIcon {
                    Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.8))
                        .transition(.scale.combined(with: .opacity))
                }

                // Video list panel
                if showVideoList {
                    HStack {
                        Spacer()
                        VideoListPanel(
                            videos: currentVideos,
                            currentVideoId: video.id,
                            onSelect: { v in
                                if let i = currentVideos.firstIndex(where: { $0.id == v.id }) {
                                    videoIndex = i
                                    currentTime = 0
                                }
                            },
                            onClose: { showVideoList = false }
                        )
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing))
                    }
                }
            }

            // Lock screen
            if isLocked {
                LockScreenView { isLocked = false }
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            restoreState()
            startWatchTimer()
            isPlaying = true  // auto-start
        }
        .onDisappear { saveState(); stopWatchTimer() }
        .animation(.easeInOut(duration: 0.2), value: showHUD)
        .animation(.easeInOut(duration: 0.2), value: showVideoList)
        .animation(.easeInOut(duration: 0.15), value: showPauseIcon)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.4))
            Text("No channels yet")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var gestureOverlay: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    // Right 20% → toggle playlist
                    if loc.x > geo.size.width * 0.8 {
                        withAnimation { showVideoList.toggle() }
                    } else {
                        togglePlayback()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let h = value.translation.width
                            let v = value.translation.height
                            if abs(h) > abs(v) {
                                h < 0 ? nextChannel() : prevChannel()
                            } else {
                                v < 0 ? nextVideo() : prevVideo()
                            }
                        }
                )
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.2)
                let ratio = currentVideo.map { v in
                    v.duration > 0 ? min(currentTime / v.duration, 1.0) : 0
                } ?? 0
                Color.white.opacity(0.8)
                    .frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 3)
        .ignoresSafeArea(edges: .horizontal)
    }

    private func channelSwitchOverlay(channel: Channel) -> some View {
        VStack(spacing: 8) {
            Image(systemName: channel.iconName)
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: channel.iconColor))
            Text(channel.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("CH \(channelIndex + 1) / \(channels.count)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Actions

    private func togglePlayback() {
        withAnimation { showVideoList = false }
        isPlaying.toggle()
        withAnimation { showPauseIcon = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { showPauseIcon = false }
        }
        flashHUD()
    }

    private func nextChannel() {
        guard channelIndex < channels.count - 1 else { return }
        saveState()
        channelIndex += 1
        videoIndex = 0
        currentTime = 0
        restoreVideoState()
        showChannelOverlay()
        flashHUD()
    }

    private func prevChannel() {
        guard channelIndex > 0 else { return }
        saveState()
        channelIndex -= 1
        videoIndex = 0
        currentTime = 0
        restoreVideoState()
        showChannelOverlay()
        flashHUD()
    }

    private func nextVideo() {
        guard videoIndex < currentVideos.count - 1 else { return }
        videoIndex += 1
        currentTime = 0
        flashHUD()
    }

    private func prevVideo() {
        guard videoIndex > 0 else { return }
        videoIndex -= 1
        currentTime = 0
        flashHUD()
    }

    private func advanceVideo() {
        if videoIndex < currentVideos.count - 1 {
            videoIndex += 1
            currentTime = 0
        } else {
            isPlaying = false
        }
    }

    private func flashHUD() {
        showHUD = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showHUD = false }
    }

    private func showChannelOverlay() {
        withAnimation { showChannelSwitch = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showChannelSwitch = false }
        }
    }

    // MARK: - State Persistence

    private func saveState() {
        guard let ch = currentChannel, let video = currentVideo else { return }
        let state = PlaybackState(channelId: ch.id, currentVideoId: video.id, currentTime: currentTime)
        store.savePlaybackState(state)
    }

    private func restoreState() {
        // Restore last channel
        if let lastId = store.settings.lastChannelId,
           let i = channels.firstIndex(where: { $0.id == lastId }) {
            channelIndex = i
        }
        restoreVideoState()
        checkLock()
    }

    private func restoreVideoState() {
        guard let ch = currentChannel else { return }
        if let state = store.playbackState(for: ch.id),
           let i = currentVideos.firstIndex(where: { $0.id == state.currentVideoId }) {
            videoIndex = i
            currentTime = state.currentTime
        }
    }

    private func checkLock() {
        isLocked = store.isTimeLimitReached || !store.isWithinAllowedTime
    }

    // MARK: - Watch Timer

    private func startWatchTimer() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            if isPlaying {
                store.addWatchTime(seconds: 10)
                checkLock()
            }
        }
    }

    private func stopWatchTimer() {
        watchTimer?.invalidate()
        watchTimer = nil
    }
}
