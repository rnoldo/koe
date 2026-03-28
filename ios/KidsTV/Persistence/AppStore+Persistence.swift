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
    }
}
