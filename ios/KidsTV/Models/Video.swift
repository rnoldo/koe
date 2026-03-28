import Foundation
import SwiftUI

struct Video: Identifiable, Codable {
    var id: String
    var title: String
    var sourceId: String
    var remotePath: String
    var duration: TimeInterval  // seconds
    var resolution: String?     // e.g. "1920x1080"
    var fileSize: Int64?        // bytes
    var thumbnailColor: String  // hex color for placeholder
    var remoteItemId: String?   // server-side ID (Emby item ID, cloud drive file ID)
    var addedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        sourceId: String,
        remotePath: String,
        duration: TimeInterval = 0,
        resolution: String? = nil,
        fileSize: Int64? = nil,
        thumbnailColor: String = "#4A90D9",
        remoteItemId: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceId = sourceId
        self.remotePath = remotePath
        self.duration = duration
        self.resolution = resolution
        self.fileSize = fileSize
        self.thumbnailColor = thumbnailColor
        self.remoteItemId = remoteItemId
        self.addedAt = addedAt
    }

    var formattedDuration: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
