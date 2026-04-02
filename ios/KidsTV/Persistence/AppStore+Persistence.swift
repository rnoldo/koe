import Foundation

private struct PersistedState: Codable {
    var sources: [MediaSource]
    var videos: [Video]
    var channels: [Channel]
    var playbackStates: [String: PlaybackState]
    var watchTimeRecords: [WatchTimeRecord]
    var settings: AppSettings
    var locale: AppStore.AppLocale
}

extension AppStore {

    private static let storageKey = "kidstv-storage"

    func save() {
        let state = PersistedState(
            sources: sources,
            videos: videos,
            channels: channels,
            playbackStates: playbackStates,
            watchTimeRecords: watchTimeRecords,
            settings: settings,
            locale: locale
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        sources = state.sources
        videos = state.videos
        channels = state.channels
        playbackStates = state.playbackStates
        watchTimeRecords = state.watchTimeRecords
        settings = state.settings
        locale = state.locale
        if sanitizeReferences() {
            save()
        }
    }

    @discardableResult
    private func sanitizeReferences() -> Bool {
        var changed = false
        let validVideoIds = Set(videos.map(\.id))
        for index in channels.indices {
            let oldCount = channels[index].videoIds.count
            channels[index].videoIds.removeAll { !validVideoIds.contains($0) }
            if channels[index].videoIds.count != oldCount {
                changed = true
            }
        }

        let validChannelIds = Set(channels.map(\.id))
        let filteredPlaybackStates = playbackStates.filter { channelId, state in
            validChannelIds.contains(channelId) && validVideoIds.contains(state.currentVideoId)
        }
        if filteredPlaybackStates.count != playbackStates.count {
            changed = true
            playbackStates = filteredPlaybackStates
        }
        return changed
    }
}
