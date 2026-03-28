import Foundation

struct Channel: Identifiable, Codable {
    var id: String
    var name: String
    var iconName: String    // SF Symbol name
    var iconColor: String   // hex color
    var defaultVolume: Double  // 0.0 – 1.0
    var sortOrder: Int
    var videoIds: [String]
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        iconName: String = "tv",
        iconColor: String = "#4A90D9",
        defaultVolume: Double = 0.8,
        sortOrder: Int = 0,
        videoIds: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.iconColor = iconColor
        self.defaultVolume = defaultVolume
        self.sortOrder = sortOrder
        self.videoIds = videoIds
        self.createdAt = createdAt
    }
}
