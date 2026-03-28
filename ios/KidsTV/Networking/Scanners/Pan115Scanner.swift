import Foundation

struct Pan115Scanner: SourceScanner {

    private let http = HTTPClient.shared

    func scan(source: MediaSource) async throws -> [Video] {
        guard let cookies = source.config.cookies, !cookies.isEmpty else {
            throw ScannerError.missingConfig("Cookies are required — paste from a logged-in browser session")
        }
        let rootId = source.config.rootFolderId ?? "0"  // "0" = root folder
        return try await listFiles(folderId: rootId, sourceId: source.id, cookies: cookies)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let cookies = source.config.cookies,
              let pickcode = video.remoteItemId else {
            throw ScannerError.authRequired
        }
        // Use the web download URL endpoint
        var c = URLComponents(string: "https://webapi.115.com/files/download")!
        c.queryItems = [URLQueryItem(name: "pickcode", value: pickcode)]
        let (data, _) = try await http.get(c.url!, headers: cookieHeaders(cookies))
        let resp = try JSONDecoder().decode(Pan115DownloadResponse.self, from: data)
        guard let urlStr = resp.file_url, let url = URL(string: urlStr) else {
            throw ScannerError.invalidURL
        }
        return StreamableMedia(url: url, httpHeaders: cookieHeaders(cookies))
    }

    // MARK: - Private

    private func listFiles(folderId: String, sourceId: String, cookies: String) async throws -> [Video] {
        let videoExts = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts"])
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]
        var videos: [Video] = []
        var offset = 0
        let limit = 1150

        while true {
            var c = URLComponents(string: "https://webapi.115.com/files")!
            c.queryItems = [
                URLQueryItem(name: "aid", value: "1"),
                URLQueryItem(name: "cid", value: folderId),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "show_dir", value: "1"),
                URLQueryItem(name: "o", value: "file_name"),
                URLQueryItem(name: "asc", value: "1"),
                URLQueryItem(name: "natsort", value: "1"),
            ]
            let (data, _) = try await http.get(c.url!, headers: cookieHeaders(cookies))
            let resp = try JSONDecoder().decode(Pan115FileList.self, from: data)

            guard let items = resp.data else { break }
            if items.isEmpty { break }

            for item in items {
                if item.fid == nil {
                    // It's a folder (folders have cid but no fid)
                    if let cid = item.cid {
                        let subVideos = try await listFiles(folderId: cid, sourceId: sourceId, cookies: cookies)
                        videos.append(contentsOf: subVideos)
                    }
                } else {
                    let name = item.n ?? "Untitled"
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard videoExts.contains(ext) else { continue }
                    let title = (name as NSString).deletingPathExtension
                    videos.append(Video(
                        title: title,
                        sourceId: sourceId,
                        remotePath: "",
                        duration: 0,
                        resolution: nil,
                        fileSize: item.s,
                        thumbnailColor: colors.randomElement()!,
                        remoteItemId: item.pc  // pickcode for download
                    ))
                }
            }

            if items.count < limit { break }
            offset += limit
        }
        return videos
    }

    private func cookieHeaders(_ cookies: String) -> [String: String] {
        ["Cookie": cookies, "User-Agent": "Mozilla/5.0"]
    }
}

// MARK: - 115 API Models

private struct Pan115FileList: Codable {
    let state: Bool?
    let data: [Pan115Item]?
}

private struct Pan115Item: Codable {
    let fid: String?    // file ID (nil for folders)
    let cid: String?    // category/folder ID
    let n: String?      // name
    let s: Int64?       // size
    let pc: String?     // pickcode (for downloads)
    let ico: String?    // file type icon
}

private struct Pan115DownloadResponse: Codable {
    let state: Bool?
    let file_url: String?
}
