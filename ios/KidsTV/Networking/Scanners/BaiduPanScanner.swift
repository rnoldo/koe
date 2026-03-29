import Foundation

struct BaiduPanScanner: SourceScanner {

    private let http = HTTPClient.shared

    // Register your app at https://pan.baidu.com/union/doc/
    static let clientId = Secrets.Baidu.clientId
    static let clientSecret = Secrets.Baidu.clientSecret
    static let callbackScheme = "kidstv"
    static let redirectURI = "kidstv://oauth/baidu"

    func scan(source: MediaSource) async throws -> [Video] {
        guard let token = source.config.accessToken, !token.isEmpty else {
            throw ScannerError.authRequired
        }
        let rootPath = source.config.rootFolderId ?? "/"
        return try await listFiles(path: rootPath, sourceId: source.id, token: token)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let token = source.config.accessToken,
              let fsId = video.remoteItemId else {
            throw ScannerError.authRequired
        }
        // Get download link via filemetas API
        var c = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/multimedia")!
        c.queryItems = [
            URLQueryItem(name: "method", value: "filemetas"),
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "fsids", value: "[\(fsId)]"),
            URLQueryItem(name: "dlink", value: "1"),
        ]
        let (data, _) = try await http.get(c.url!, headers: [:])
        let resp = try JSONDecoder().decode(BaiduFileMetaResponse.self, from: data)
        guard let dlink = resp.list.first?.dlink else { throw ScannerError.invalidURL }
        // Append access_token to dlink
        let dlURL = URL(string: "\(dlink)&access_token=\(token)")!
        // Baidu requires a User-Agent header for downloads
        return StreamableMedia(url: dlURL, httpHeaders: ["User-Agent": "pan.baidu.com"])
    }

    // MARK: - Auth Flow

    static var authURL: URL {
        var c = URLComponents(string: "https://openapi.baidu.com/oauth/2.0/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "basic,netdisk"),
        ]
        return c.url!
    }

    static let tokenURL = URL(string: "https://openapi.baidu.com/oauth/2.0/token")!

    // MARK: - Private

    private func listFiles(path: String, sourceId: String, token: String) async throws -> [Video] {
        let videoExts = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts"])
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]
        var videos: [Video] = []
        var start = 0
        let limit = 1000

        while true {
            var c = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
            c.queryItems = [
                URLQueryItem(name: "method", value: "list"),
                URLQueryItem(name: "access_token", value: token),
                URLQueryItem(name: "dir", value: path),
                URLQueryItem(name: "start", value: "\(start)"),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "order", value: "name"),
            ]
            let (data, _) = try await http.get(c.url!, headers: [:])
            let resp = try JSONDecoder().decode(BaiduFileListResponse.self, from: data)

            guard let list = resp.list else { break }
            if list.isEmpty { break }

            for item in list {
                if item.isdir == 1 {
                    let subVideos = try await listFiles(path: item.path, sourceId: sourceId, token: token)
                    videos.append(contentsOf: subVideos)
                } else {
                    let ext = (item.server_filename as NSString).pathExtension.lowercased()
                    guard videoExts.contains(ext) else { continue }
                    let title = (item.server_filename as NSString).deletingPathExtension
                    videos.append(Video(
                        title: title,
                        sourceId: sourceId,
                        remotePath: "",
                        duration: 0,
                        resolution: nil,
                        fileSize: item.size,
                        thumbnailColor: colors.randomElement()!,
                        remoteItemId: "\(item.fs_id)"
                    ))
                }
            }

            if list.count < limit { break }
            start += limit
        }
        return videos
    }
}

// MARK: - Baidu API Models

private struct BaiduFileListResponse: Codable {
    let errno: Int?
    let list: [BaiduFileItem]?
}

private struct BaiduFileItem: Codable {
    let fs_id: Int64
    let path: String
    let server_filename: String
    let size: Int64?
    let isdir: Int  // 1 = folder, 0 = file
}

private struct BaiduFileMetaResponse: Codable {
    let list: [BaiduFileMeta]
}

private struct BaiduFileMeta: Codable {
    let dlink: String?
    let filename: String?
}
