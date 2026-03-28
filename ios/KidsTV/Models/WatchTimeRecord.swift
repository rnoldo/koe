import Foundation

struct WatchTimeRecord: Codable {
    var date: String        // "YYYY-MM-DD"
    var totalSeconds: Int

    static var todayKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: .now)
    }
}
