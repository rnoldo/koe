import Foundation

struct PlaybackState: Codable {
    var channelId: String
    var currentVideoId: String
    var currentTime: TimeInterval
    var updatedAt: Date

    init(channelId: String, currentVideoId: String, currentTime: TimeInterval = 0) {
        self.channelId = channelId
        self.currentVideoId = currentVideoId
        self.currentTime = currentTime
        self.updatedAt = .now
    }
}
