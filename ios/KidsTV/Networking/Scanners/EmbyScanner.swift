import Foundation

struct EmbyScanner: SourceScanner {

    private let http = HTTPClient.shared

    func scan(source: MediaSource) async throws -> [Video] {
        guard let serverUrl = source.config.serverUrl?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let apiKey = source.config.apiKey,
              let userId = source.config.userId,
              let baseURL = URL(string: serverUrl) else {
            throw ScannerError.missingConfig("Server URL, API Key, and User ID are required")
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("/Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode,Video"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Path,MediaSources,Overview"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        guard let url = components.url else { throw ScannerError.invalidURL }

        let headers = authHeaders(apiKey: apiKey)
        let (data, _) = try await http.get(url, headers: headers)
        let response = try JSONDecoder().decode(EmbyItemsResponse.self, from: data)

        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C","#E67E22","#1A252F"]

        return response.Items.compactMap { item -> Video? in
            guard item.itemType == "Movie" || item.itemType == "Episode" || item.itemType == "Video" else { return nil }
            let duration = TimeInterval(item.RunTimeTicks ?? 0) / 10_000_000  // ticks → seconds
            let resolution: String? = {
                guard let ms = item.MediaSources?.first,
                      let stream = ms.MediaStreams?.first(where: { $0.streamType == "Video" }) else { return nil }
                return "\(stream.Width ?? 0)x\(stream.Height ?? 0)"
            }()
            let fileSize: Int64? = item.MediaSources?.first?.Size

            return Video(
                title: item.Name ?? "Untitled",
                sourceId: source.id,
                remotePath: "\(serverUrl)/Videos/\(item.Id)/stream?Static=true&api_key=\(apiKey)",
                duration: duration,
                resolution: resolution,
                fileSize: fileSize,
                thumbnailColor: colors.randomElement()!,
                remoteItemId: item.Id
            )
        }
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let serverUrl = source.config.serverUrl?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let apiKey = source.config.apiKey,
              let itemId = video.remoteItemId else {
            return StreamableMedia(url: URL(string: video.remotePath)!, httpHeaders: [:])
        }
        let urlStr = "\(serverUrl)/Videos/\(itemId)/stream?Static=true&api_key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw ScannerError.invalidURL }
        return StreamableMedia(url: url, httpHeaders: authHeaders(apiKey: apiKey))
    }

    private func authHeaders(apiKey: String) -> [String: String] {
        ["X-MediaBrowser-Token": apiKey]
    }
}

// MARK: - Emby API Response Models

private struct EmbyItemsResponse: Codable {
    let Items: [EmbyItem]
    let TotalRecordCount: Int?
}

private struct EmbyItem: Codable {
    let Id: String
    let Name: String?
    let itemType: String?
    let RunTimeTicks: Int64?
    let MediaSources: [EmbyMediaSource]?

    enum CodingKeys: String, CodingKey {
        case Id, Name, RunTimeTicks, MediaSources
        case itemType = "Type"
    }
}

private struct EmbyMediaSource: Codable {
    let Size: Int64?
    let Path: String?
    let MediaStreams: [EmbyMediaStream]?
}

private struct EmbyMediaStream: Codable {
    let streamType: String?
    let Width: Int?
    let Height: Int?

    enum CodingKeys: String, CodingKey {
        case Width, Height
        case streamType = "Type"
    }
}
