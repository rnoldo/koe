import Foundation

struct BaiduPanScanner: SourceScanner {

    private let http = HTTPClient.shared
    private let streamingRequestHeaders = [
        "User-Agent": "pan.baidu.com",
        "Referer": "https://pan.baidu.com/"
    ]

    // Register your app at https://pan.baidu.com/union/doc/
    static let clientId = Secrets.Baidu.clientId
    static let clientSecret = Secrets.Baidu.clientSecret
    static let callbackScheme = "bdconnect"
    static let redirectURI = "bdconnect://oauth"

    func scan(source: MediaSource) async throws -> [Video] {
        guard let token = source.config.accessToken, !token.isEmpty else {
            throw ScannerError.authRequired
        }
        let rootPath = source.config.rootFolderId ?? "/"
        return try await listFiles(path: rootPath, sourceId: source.id, token: token)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let token = source.config.accessToken else {
            throw ScannerError.authRequired
        }
        let path = video.remotePath
        guard !path.isEmpty else { throw ScannerError.invalidURL }

        // Baidu Pan streaming API (https://pan.baidu.com/union/doc/aksk0bacn)
        // Two-step process: first get adToken, then fetch M3U8 with it.
        // error_code 31341 means transcoding in progress — retry up to 3 times.
        let baseURL = streamingRequestURL(token: token, path: path, type: "M3U8_AUTO_720")

        // Step 1: Request with nom3u8=1 to get adToken and wait time
        let step1 = try await fetchStreamingMeta(baseURL: baseURL)

        NSLog("%@", "[KidsTV][Baidu] step1: errno=\(step1.errno as Any) error_code=\(step1.error_code as Any) adToken=\(step1.adToken?.prefix(20) as Any) ltime=\(step1.ltime as Any) adTime=\(step1.adTime as Any)")

        // Step 2+: Fetch M3U8, retrying on errno:133 (Baidu ad-wait mechanism).
        // Baidu requires waiting `adTime` seconds and re-requesting with a fresh adToken.
        let waitTime = adWaitTime(for: step1)
        if waitTime > 0 {
            try await Task.sleep(for: .seconds(waitTime))
        }

        let playlist = try await fetchM3U8(baseURL: baseURL, adToken: step1.adToken ?? "")
        logOriginalPlaylistDiagnostics(playlist.content)

        let requestHeaders = [
            "User-Agent": "xpanvideo;KidsTV;1.0.0;iOS;1;ts",
            "Referer": "https://pan.baidu.com/"
        ]
        let segments = resolvedSegments(from: playlist.content, baseURL: playlist.finalURL)
        let totalDuration = segments.reduce(0) { $0 + $1.duration }
        NSLog(
            "%@",
            "[KidsTV][Baidu] segment queue ready: count=\(segments.count) totalDuration=\(Int(totalDuration))s first=\(segments.first?.url.absoluteString ?? "nil")"
        )

        return try await BaiduPlaybackPipeline.shared.preparePlayableMedia(
            video: video,
            segments: segments,
            headers: requestHeaders
        )
    }

    private func logOriginalPlaylistDiagnostics(_ playlist: String) {
        let lines = playlist.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let interesting = lines.filter {
            $0.hasPrefix("#EXT-X-VERSION") ||
            $0.hasPrefix("#EXT-X-TARGETDURATION") ||
            $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE") ||
            $0.hasPrefix("#EXT-X-MAP") ||
            $0.hasPrefix("#EXT-X-KEY") ||
            $0.hasPrefix("#EXT-X-INDEPENDENT-SEGMENTS") ||
            $0.hasPrefix("#EXT-X-ENDLIST") ||
            $0.hasPrefix("#EXTINF") ||
            (!$0.hasPrefix("#") && !$0.isEmpty)
        }
        let preview = interesting.prefix(16).joined(separator: " | ")
        NSLog("%@", "[KidsTV][Baidu] original M3U8 directives: \(preview.prefix(1200))")
    }

    private func resolvedSegments(from playlist: String, baseURL: URL) -> [ResolvedBaiduSegment] {
        var originalURLs: [URL] = []
        var durations: [Double] = []
        var pendingDuration: Double?

        for rawLine in playlist.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                let value = line
                    .dropFirst("#EXTINF:".count)
                    .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                pendingDuration = value.flatMap { Double($0) }
                continue
            }

            guard !line.hasPrefix("#") else { continue }

            let absoluteURL: URL?
            if line.hasPrefix("http://") || line.hasPrefix("https://") {
                absoluteURL = URL(string: line)
            } else {
                absoluteURL = URL(string: line, relativeTo: baseURL)?.absoluteURL
            }

            guard let absoluteURL else { continue }
            originalURLs.append(absoluteURL)
            durations.append(pendingDuration ?? 0)
            pendingDuration = nil
        }

        return zip(originalURLs, durations).map { url, duration in
            ResolvedBaiduSegment(url: url, duration: duration)
        }
    }

    /// Fetch M3U8 content, retrying on errno:133 (Baidu ad-wait mechanism).
    private func fetchM3U8(baseURL: URL, adToken: String, maxRetries: Int = 12) async throws -> BaiduM3U8Playlist {
        var currentAdToken = adToken
        for attempt in 1...maxRetries {
            var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            if !currentAdToken.isEmpty {
                c.queryItems?.append(URLQueryItem(name: "adToken", value: currentAdToken))
            }
            let url = c.url!
            NSLog("%@", "[KidsTV][Baidu] fetchM3U8 attempt \(attempt) url: \(url.absoluteString.prefix(200))")
            let data: Data
            let responseURL: URL
            do {
                let (receivedData, response) = try await http.get(url, headers: streamingRequestHeaders)
                data = receivedData
                responseURL = response.url ?? url
            } catch let HTTPError.badStatus(_, body) {
                data = body
                responseURL = url
            }
            let responsePreview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            NSLog("%@", "[KidsTV][Baidu] fetchM3U8 attempt \(attempt) response: \(responsePreview)")
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") {
                return BaiduM3U8Playlist(content: text, finalURL: responseURL)
            }
            if let resp = decodeStreamingResponse(from: data),
               resp.errno == 133 {
                let wait = adWaitTime(for: resp)
                if let newToken = resp.adToken, !newToken.isEmpty {
                    currentAdToken = newToken
                }
                NSLog("%@", "[KidsTV][Baidu] errno:133 ad-wait \(wait)s (attempt \(attempt)/\(maxRetries))")
                if attempt < maxRetries {
                    do {
                        let refreshed = try await fetchStreamingMeta(baseURL: baseURL, maxRetries: 1)
                        if let refreshedToken = refreshed.adToken, !refreshedToken.isEmpty {
                            currentAdToken = refreshedToken
                        }
                        let refreshWait = max(wait, adWaitTime(for: refreshed))
                        NSLog("%@", "[KidsTV][Baidu] refreshed adToken after 133, wait=\(refreshWait)")
                        if refreshWait > 0 {
                            try await Task.sleep(for: .seconds(refreshWait))
                        }
                    } catch {
                        NSLog("%@", "[KidsTV][Baidu] adToken refresh skipped: \(error.localizedDescription)")
                        try await Task.sleep(for: .seconds(wait))
                    }
                    continue
                }
                throw ScannerError.serverError("Baidu is still asking for ad wait after \(maxRetries) retries. errno=133")
            }
            throw ScannerError.serverError("Unexpected Baidu response: \(responsePreview)")
        }
        throw ScannerError.serverError("Failed to get M3U8 after \(maxRetries) retries")
    }

    private func decodeStreamingResponse(from data: Data) -> BaiduStreamingResponse? {
        if let resp = try? JSONDecoder().decode(BaiduStreamingResponse.self, from: data) {
            return resp
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return BaiduStreamingResponse(
            errno: json["errno"] as? Int,
            error_code: json["error_code"] as? Int,
            request_id: json["request_id"] as? Int64 ?? (json["request_id"] as? NSNumber)?.int64Value,
            adTime: json["adTime"] as? Int,
            adToken: json["adToken"] as? String,
            ltime: json["ltime"] as? Int
        )
    }

    /// Fetch streaming metadata, retrying on error_code 31341 (transcoding in progress).
    private func fetchStreamingMeta(baseURL: URL, maxRetries: Int = 3) async throws -> BaiduStreamingResponse {
        var step1Components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        step1Components.queryItems?.append(URLQueryItem(name: "nom3u8", value: "1"))
        let url = step1Components.url!

        for attempt in 1...maxRetries {
            let data: Data
            do {
                let (d, _) = try await http.get(url, headers: streamingRequestHeaders)
                data = d
            } catch let HTTPError.badStatus(_, body) {
                // Baidu returns HTTP 400 for some streaming errors but includes JSON body
                data = body
            }

            let resp = try JSONDecoder().decode(BaiduStreamingResponse.self, from: data)

            if resp.error_code == 31341 {
                if attempt < maxRetries {
                    try await Task.sleep(for: .seconds(3))
                    continue
                }
                throw ScannerError.serverError("Video is being transcoded by Baidu. Try again in a few minutes.")
            }

            if let errorCode = resp.error_code, errorCode != 0 {
                throw ScannerError.serverError(Self.errorMessage(for: errorCode))
            }

            return resp
        }

        throw ScannerError.serverError("Baidu streaming failed after \(maxRetries) retries")
    }

    private static func errorMessage(for code: Int) -> String {
        switch code {
        case 31024: return "Access denied"
        case 31066: return "File not found"
        case 31339: return "This video cannot be played"
        case 31341: return "Video is being transcoded. Try again in a few minutes."
        case 31346: return "Video transcoding failed"
        default:    return "Baidu streaming error \(code)"
        }
    }

    private func streamingRequestURL(token: String, path: String, type: String) -> URL {
        var c = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
        c.queryItems = [
            URLQueryItem(name: "method", value: "streaming"),
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "type", value: type),
        ]
        return c.url!
    }

    private func adWaitTime(for response: BaiduStreamingResponse) -> Int {
        max(response.ltime ?? 0, response.adTime ?? 0, 5)
    }

    // MARK: - Auth Flow

    static var authURL: URL {
        var c = URLComponents(string: "https://openapi.baidu.com/oauth/2.0/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "basic netdisk"),
            URLQueryItem(name: "display", value: "touch"),   // mobile UI
            URLQueryItem(name: "locale", value: "zh_CN"),    // Chinese
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
                        remotePath: item.path,
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

private struct BaiduStreamingResponse: Codable {
    let errno: Int?
    let error_code: Int?
    let request_id: Int64?
    let adTime: Int?
    let adToken: String?
    let ltime: Int?
}

private struct BaiduM3U8Playlist {
    let content: String
    let finalURL: URL
}
