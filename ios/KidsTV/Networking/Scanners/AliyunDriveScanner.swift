import Foundation

struct AliyunDriveScanner: SourceScanner {

    private let http = HTTPClient.shared
    private let baseAPI = "https://open.alipan.com"

    // Register your app at https://open.alipan.com/ to get these
    static let clientId = Secrets.Aliyun.clientId
    static let callbackScheme = "kidstv"
    static let redirectURI = "kidstv://oauth/aliyun"

    func scan(source: MediaSource) async throws -> [Video] {
        guard let token = source.config.accessToken, !token.isEmpty else {
            throw ScannerError.authRequired
        }
        let driveId = try await getDriveId(token: token)
        let parentId = source.config.rootFolderId ?? "root"
        return try await listFiles(driveId: driveId, parentId: parentId, sourceId: source.id, token: token)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let token = source.config.accessToken,
              let fileId = video.remoteItemId else {
            throw ScannerError.authRequired
        }
        let driveId = try await getDriveId(token: token)
        let url = URL(string: "\(baseAPI)/adrive/v1.0/openFile/getDownloadUrl")!
        let body = try JSONEncoder().encode(["drive_id": driveId, "file_id": fileId])
        let (data, _) = try await http.post(url, body: body, headers: authHeaders(token))
        let resp = try JSONDecoder().decode(AliyunDownloadResponse.self, from: data)
        guard let dlURL = URL(string: resp.url) else { throw ScannerError.invalidURL }
        // Pre-signed URL, no extra headers needed
        return StreamableMedia(url: dlURL, httpHeaders: [:])
    }

    // MARK: - Auth Flow

    static var authURL: URL {
        var c = URLComponents(string: "https://open.alipan.com/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user:base,file:all:read"),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        return c.url!
    }

    static let tokenURL = URL(string: "https://open.alipan.com/oauth/access_token")!

    // MARK: - Private

    private func getDriveId(token: String) async throws -> String {
        let url = URL(string: "\(baseAPI)/adrive/v1.0/user/getDriveInfo")!
        let (data, _) = try await http.post(url, body: "{}".data(using: .utf8), headers: authHeaders(token))
        let resp = try JSONDecoder().decode(AliyunDriveInfo.self, from: data)
        return resp.default_drive_id
    }

    private func listFiles(driveId: String, parentId: String, sourceId: String, token: String) async throws -> [Video] {
        let videoExts = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts"])
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]
        var videos: [Video] = []
        var marker: String? = nil

        repeat {
            let url = URL(string: "\(baseAPI)/adrive/v1.0/openFile/list")!
            var params: [String: Any] = [
                "drive_id": driveId,
                "parent_file_id": parentId,
                "limit": 100,
                "order_by": "name",
                "order_direction": "ASC",
            ]
            if let m = marker { params["marker"] = m }
            let body = try JSONSerialization.data(withJSONObject: params)
            let (data, _) = try await http.post(url, body: body, headers: authHeaders(token))
            let resp = try JSONDecoder().decode(AliyunFileList.self, from: data)

            for item in resp.items {
                if item.type == "folder" {
                    let subVideos = try await listFiles(driveId: driveId, parentId: item.file_id, sourceId: sourceId, token: token)
                    videos.append(contentsOf: subVideos)
                } else {
                    let ext = (item.name as NSString).pathExtension.lowercased()
                    guard videoExts.contains(ext) else { continue }
                    let title = (item.name as NSString).deletingPathExtension
                    videos.append(Video(
                        title: title,
                        sourceId: sourceId,
                        remotePath: "",  // resolved at playback time
                        duration: 0,
                        resolution: nil,
                        fileSize: item.size,
                        thumbnailColor: colors.randomElement()!,
                        remoteItemId: item.file_id
                    ))
                }
            }
            marker = resp.next_marker
        } while marker != nil && !marker!.isEmpty

        return videos
    }

    private func authHeaders(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }
}

// MARK: - Aliyun API Models

private struct AliyunDriveInfo: Codable {
    let default_drive_id: String
}

private struct AliyunFileList: Codable {
    let items: [AliyunFileItem]
    let next_marker: String?
}

private struct AliyunFileItem: Codable {
    let file_id: String
    let name: String
    let type: String  // "file" or "folder"
    let size: Int64?
}

private struct AliyunDownloadResponse: Codable {
    let url: String
    let expiration: String?
}
