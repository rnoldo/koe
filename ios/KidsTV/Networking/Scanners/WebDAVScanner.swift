import Foundation

struct WebDAVScanner: SourceScanner {

    private let http = HTTPClient.shared
    private let videoExtensions = Set(["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts", "m2ts"])

    func scan(source: MediaSource) async throws -> [Video] {
        guard let urlStr = source.config.url?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              let baseURL = URL(string: urlStr) else {
            throw ScannerError.missingConfig("WebDAV URL is required")
        }
        let headers = authHeaders(for: source)
        return try await scanDirectory(baseURL: baseURL, path: "/", sourceId: source.id, headers: headers)
    }

    func streamingURL(for video: Video, source: MediaSource) async throws -> StreamableMedia {
        guard let url = URL(string: video.remotePath) else { throw ScannerError.invalidURL }
        return StreamableMedia(url: url, httpHeaders: authHeaders(for: source))
    }

    // MARK: - Private

    private func scanDirectory(baseURL: URL, path: String, sourceId: String, headers: [String: String]) async throws -> [Video] {
        let url = baseURL.appendingPathComponent(path)
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getcontenttype/>
                <D:resourcetype/>
            </D:prop>
        </D:propfind>
        """.data(using: .utf8)

        var hdrs = headers
        hdrs["Depth"] = "1"
        hdrs["Content-Type"] = "application/xml"

        let (data, _) = try await http.send(method: "PROPFIND", url: url, body: propfindBody, headers: hdrs)

        let parser = WebDAVResponseParser(data: data)
        let entries = parser.parse()

        var videos: [Video] = []
        let colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C"]

        for entry in entries {
            // Skip the directory itself
            let entryPath = entry.href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let currentPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if entryPath == currentPath || entry.href == path { continue }

            if entry.isDirectory {
                // Recurse into subdirectories
                let subVideos = try await scanDirectory(
                    baseURL: baseURL, path: entry.href,
                    sourceId: sourceId, headers: headers
                )
                videos.append(contentsOf: subVideos)
            } else {
                let ext = (entry.href as NSString).pathExtension.lowercased()
                guard videoExtensions.contains(ext) else { continue }
                let title = ((entry.href as NSString).lastPathComponent as NSString).deletingPathExtension
                let streamURL = baseURL.appendingPathComponent(entry.href)

                videos.append(Video(
                    title: entry.displayName ?? title,
                    sourceId: sourceId,
                    remotePath: streamURL.absoluteString,
                    duration: 0,  // WebDAV doesn't provide duration
                    resolution: nil,
                    fileSize: entry.contentLength,
                    thumbnailColor: colors.randomElement()!
                ))
            }
        }
        return videos
    }

    private func authHeaders(for source: MediaSource) -> [String: String] {
        guard let username = source.config.username, !username.isEmpty,
              let password = source.config.password else { return [:] }
        return ["Authorization": HTTPClient.basicAuthHeader(username: username, password: password)]
    }
}

// MARK: - WebDAV XML Response Parser

private struct WebDAVEntry {
    var href: String = ""
    var displayName: String?
    var contentLength: Int64?
    var contentType: String?
    var isDirectory: Bool = false
}

private class WebDAVResponseParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var entries: [WebDAVEntry] = []
    private var current: WebDAVEntry?
    private var currentElement = ""
    private var textBuffer = ""

    init(data: Data) { self.data = data }

    func parse() -> [WebDAVEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = element.components(separatedBy: ":").last ?? element
        currentElement = local
        textBuffer = ""
        if local == "response" { current = WebDAVEntry() }
        if local == "collection" { current?.isDirectory = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        let local = element.components(separatedBy: ":").last ?? element
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch local {
        case "href":
            current?.href = text
        case "displayname":
            if !text.isEmpty { current?.displayName = text }
        case "getcontentlength":
            current?.contentLength = Int64(text)
        case "getcontenttype":
            current?.contentType = text
        case "response":
            if let entry = current { entries.append(entry) }
            current = nil
        default: break
        }
    }
}
