import Foundation

struct AppSettings: Codable {
    var pin: String
    var dailyLimitMinutes: Int?     // nil = unlimited
    var allowedStartTime: String?   // "HH:mm" or nil
    var allowedEndTime: String?     // "HH:mm" or nil
    var maxVolume: Double           // 0.0 – 1.0
    var lastChannelId: String?

    init(
        pin: String = "1234",
        dailyLimitMinutes: Int? = nil,
        allowedStartTime: String? = nil,
        allowedEndTime: String? = nil,
        maxVolume: Double = 0.8,
        lastChannelId: String? = nil
    ) {
        self.pin = pin
        self.dailyLimitMinutes = dailyLimitMinutes
        self.allowedStartTime = allowedStartTime
        self.allowedEndTime = allowedEndTime
        self.maxVolume = maxVolume
        self.lastChannelId = lastChannelId
    }
}
