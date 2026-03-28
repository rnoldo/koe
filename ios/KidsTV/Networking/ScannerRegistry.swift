import Foundation

struct ScannerRegistry {
    static func scanner(for type: SourceType) -> SourceScanner? {
        switch type {
        case .local: return nil  // handled directly by AppStore
        case .emby: return EmbyScanner()
        case .jellyfin: return JellyfinScanner()
        case .webdav: return WebDAVScanner()
        case .smb: return SMBScanner()
        case .aliyunDrive: return AliyunDriveScanner()
        case .baiduPan: return BaiduPanScanner()
        case .pan115: return Pan115Scanner()
        }
    }
}
