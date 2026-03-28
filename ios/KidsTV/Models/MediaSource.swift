import Foundation

enum SourceType: String, Codable, CaseIterable {
    case local
    case webdav
    case smb
    case aliyunDrive
    case baiduPan
    case pan115
    case emby
    case jellyfin

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .webdav: return "WebDAV"
        case .smb: return "SMB"
        case .aliyunDrive: return "Aliyun Drive"
        case .baiduPan: return "Baidu Pan"
        case .pan115: return "115 Pan"
        case .emby: return "Emby"
        case .jellyfin: return "Jellyfin"
        }
    }
}

enum ScanStatus: String, Codable {
    case idle
    case scanning
    case error
}

struct SourceConfig: Codable {
    // Local
    var dirPath: String?
    var dirBookmark: Data?   // security-scoped bookmark for re-access
    // WebDAV
    var url: String?
    var username: String?
    var password: String?
    // SMB
    var host: String?
    var share: String?
    // Emby / Jellyfin
    var serverUrl: String?
    var apiKey: String?
    var userId: String?
    // Cloud drives
    var rootFolderId: String?
    // OAuth tokens (for cloud drives)
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiry: Date?
    // 115 Pan cookie auth
    var cookies: String?
    // SMB sub-path within share
    var smbPath: String?
}

struct MediaSource: Identifiable, Codable {
    var id: String
    var name: String
    var type: SourceType
    var config: SourceConfig
    var isEnabled: Bool
    var scanStatus: ScanStatus
    var lastScanDate: Date?
    var videoCount: Int
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        type: SourceType,
        config: SourceConfig = SourceConfig(),
        isEnabled: Bool = true,
        scanStatus: ScanStatus = .idle,
        lastScanDate: Date? = nil,
        videoCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
        self.isEnabled = isEnabled
        self.scanStatus = scanStatus
        self.lastScanDate = lastScanDate
        self.videoCount = videoCount
        self.errorMessage = errorMessage
    }
}
