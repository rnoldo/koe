import Foundation

/// A lightweight local HTTP proxy that injects custom headers into requests.
/// The app connects to http://127.0.0.1:PORT/... and the proxy forwards
/// requests to the real server with the required headers (e.g., User-Agent).
/// For M3U8 playlists, segment URLs are rewritten to route through the proxy.
final class LocalStreamProxy {

    static let shared = LocalStreamProxy()

    private var server: HTTPServer?
    private(set) var port: UInt16 = 0
    private var headers: [String: String] = [:]
    private let urlMapLock = NSLock()
    private var proxiedURLMap: [String: URL] = [:]
    private var playlistMap: [String: String] = [:]
    private var nextTokenMap: [String: String] = [:]
    private var prefetchedBodies: [String: PrefetchedBody] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    /// Start the proxy with the given headers to inject on every upstream request.
    func start(headers: [String: String]) {
        self.headers = headers          // always update, even if already running
        if server != nil { return }

        let server = HTTPServer { [weak self] request in
            await self?.handleRequest(request) ?? HTTPResponse(status: 500, body: Data())
        }
        self.server = server
        self.port = server.port
        NSLog("%@", "[KidsTV][Proxy] Started on port \(port)")
    }

    func stop() {
        server?.stop()
        server = nil
        port = 0
        urlMapLock.lock()
        proxiedURLMap.removeAll()
        playlistMap.removeAll()
        nextTokenMap.removeAll()
        prefetchedBodies.removeAll()
        let tasks = Array(prefetchTasks.values)
        prefetchTasks.removeAll()
        urlMapLock.unlock()
        tasks.forEach { $0.cancel() }
    }

    func playlistURL(for playlist: String) -> URL {
        let token = UUID().uuidString
        urlMapLock.lock()
        playlistMap[token] = playlist
        urlMapLock.unlock()

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/playlist/\(token).m3u8"
        return components.url!
    }

    /// Build a proxy URL that routes through localhost.
    /// `originalURL` is the real upstream URL (e.g., Baidu M3U8 or TS segment URL).
    func proxyURL(for originalURL: URL) -> URL {
        let token = register(originalURL: originalURL)
        return proxyURL(forToken: token, originalURL: originalURL)
    }

    func proxyURLs(for originalURLs: [URL]) -> [URL] {
        guard !originalURLs.isEmpty else { return [] }

        let tokens = originalURLs.map { _ in UUID().uuidString }
        urlMapLock.lock()
        for (token, url) in zip(tokens, originalURLs) {
            proxiedURLMap[token] = url
        }
        for index in 0..<(tokens.count - 1) {
            nextTokenMap[tokens[index]] = tokens[index + 1]
        }
        urlMapLock.unlock()

        return zip(tokens, originalURLs).map { token, url in
            proxyURL(forToken: token, originalURL: url)
        }
    }

    private func proxyURL(forToken token: String, originalURL: URL) -> URL {
        let ext = inferredProxyPathExtension(for: originalURL).map { ".\($0)" } ?? ""
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/proxy/\(token)\(ext)"
        return components.url!
    }

    // MARK: - Request Handling

    private func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
        NSLog("%@", "[KidsTV][Proxy] Request \(request.method) \(request.path) query=\(request.queryParams)")
        NSLog("%@", "[KidsTV][Proxy] Request headers: \(request.headers)")

        if let token = playlistToken(from: request.path) {
            guard let playlist = resolveRegisteredPlaylist(for: token) else {
                NSLog("%@", "[KidsTV][Proxy] Playlist miss for token \(token)")
                return HTTPResponse(status: 404, body: "Playlist not found".data(using: .utf8)!)
            }
            NSLog("%@", "[KidsTV][Proxy] Serving playlist token \(token) (\(playlist.utf8.count)B)")
            return makeLocalBodyResponse(
                body: Data(playlist.utf8),
                contentType: "application/vnd.apple.mpegurl",
                requestRange: request.headers["Range"] ?? request.headers["range"]
            )
        }

        let upstreamURL: URL
        if let token = proxyToken(from: request.path),
           let registeredURL = resolveRegisteredURL(for: token) {
            upstreamURL = registeredURL
        } else if let token = request.queryParams["id"],
                  let registeredURL = resolveRegisteredURL(for: token) {
            // Backward compatibility for already-written playlists using ?id=<token>.
            upstreamURL = registeredURL
        } else if let urlParam = request.queryParams["url"],
                  let legacyURL = URL(string: urlParam) {
            // Backward compatibility for already-written playlists using ?url=<original>.
            upstreamURL = legacyURL
        } else {
            return HTTPResponse(status: 400, body: "Missing proxy target".data(using: .utf8)!)
        }

        NSLog("%@", "[KidsTV][Proxy] → \(request.method) \(upstreamURL.host ?? "?") \(upstreamURL.path.prefix(60))")

        do {
            if let cached = cachedBody(for: tokenOrNil(from: request, upstreamURL: upstreamURL)),
               request.headers["range"] == nil,
               request.headers["Range"] == nil {
                NSLog("%@", "[KidsTV][Proxy] Cache hit \(cached.token) \(cached.body.count)B \(cached.mediaType)")
                triggerPrefetch(afterServing: cached.token)
                return HTTPResponse(
                    status: 200,
                    headers: [
                        "Content-Type": cached.mediaType,
                        "Content-Length": "\(cached.body.count)",
                        "Accept-Ranges": "bytes",
                        "Cache-Control": cached.cacheControl
                    ],
                    body: cached.body
                )
            }

            var upstream = URLRequest(url: upstreamURL)
            for (key, value) in headers {
                upstream.setValue(value, forHTTPHeaderField: key)
            }
            // Forward Range header from the player if present
            if let range = request.headers["range"] ?? request.headers["Range"] {
                upstream.setValue(range, forHTTPHeaderField: "Range")
            }

            let (data, response) = try await URLSession.shared.data(for: upstream)

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(status: 502, body: Data())
            }

            guard (200..<400).contains(httpResponse.statusCode) else {
                NSLog("%@", "[KidsTV][Proxy] Upstream HTTP \(httpResponse.statusCode) for \(upstreamURL.host ?? "")")
                return HTTPResponse(
                    status: httpResponse.statusCode,
                    headers: ["Content-Type": httpResponse.mimeType ?? "application/octet-stream"],
                    body: data
                )
            }

            // Detect M3U8 and rewrite segment URLs to route through the proxy
            if isM3U8(data: data, mimeType: httpResponse.mimeType, url: upstreamURL) {
                guard let playlist = String(data: data, encoding: .utf8) else {
                    return HTTPResponse(status: 502, body: data)
                }
                // Log structure for debugging
                let allLines = playlist.split(separator: "\n", omittingEmptySubsequences: true)
                let segCount = allLines.filter { $0.hasPrefix("#EXTINF") }.count
                let discCount = allLines.filter { $0.hasPrefix("#EXT-X-DISCONTINUITY") }.count
                let hasEndList = allLines.contains { $0.hasPrefix("#EXT-X-ENDLIST") }
                NSLog("%@", "[KidsTV][Proxy] M3U8 stats: \(segCount) segments, endList=\(hasEndList), discontinuities=\(discCount)")
                // Print lines 3-8 to see structure around first segment boundary
                let middleLines = allLines.dropFirst(2).prefix(6)
                NSLog("%@", "[KidsTV][Proxy] M3U8 lines 3-8: \(middleLines.map { String($0.prefix(80)) }.joined(separator: " | "))")
                let rewritten = rewriteM3U8(playlist, baseURL: httpResponse.url ?? upstreamURL)
                let rewrittenData = Data(rewritten.utf8)
                NSLog("%@", "[KidsTV][Proxy] M3U8 rewritten (\(rewrittenData.count) bytes, mime=\(httpResponse.mimeType ?? "nil"))")
                return makeLocalBodyResponse(
                    body: rewrittenData,
                    contentType: "application/vnd.apple.mpegurl",
                    cacheControl: headerValue("Cache-Control", from: httpResponse) ?? "no-store",
                    requestRange: request.headers["Range"] ?? request.headers["range"]
                )
            }

            // TS segments or other binary content — pass through
            let mediaType = inferredMediaType(for: upstreamURL, response: httpResponse, data: data)
            NSLog("%@", "[KidsTV][Proxy] ← \(httpResponse.statusCode) \(data.count)B \(mediaType) bytes=\(hexPrefix(data, count: 16))")
            if let token = tokenOrNil(from: request, upstreamURL: upstreamURL),
               request.headers["range"] == nil,
               request.headers["Range"] == nil,
               httpResponse.statusCode == 200 {
                storePrefetchedBody(
                    token: token,
                    body: data,
                    mediaType: mediaType,
                    cacheControl: headerValue("Cache-Control", from: httpResponse) ?? "no-store"
                )
                triggerPrefetch(afterServing: token)
            }
            return HTTPResponse(
                status: httpResponse.statusCode,
                headers: passthroughHeaders(from: httpResponse, mediaType: mediaType, bodyLength: data.count),
                body: data
            )
        } catch {
            NSLog("%@", "[KidsTV][Proxy] Error fetching \(upstreamURL.host ?? ""): \(error.localizedDescription)")
            return HTTPResponse(status: 502, body: error.localizedDescription.data(using: .utf8)!)
        }
    }

    // MARK: - M3U8

    private func isM3U8(data: Data, mimeType: String?, url: URL? = nil) -> Bool {
        if let prefix = String(data: data.prefix(50), encoding: .utf8),
           prefix.contains("#EXTM3U") {
            return true
        }
        if let mime = mimeType?.lowercased(),
           mime.contains("mpegurl") || mime.contains("m3u") {
            return true
        }
        if let ext = url?.pathExtension.lowercased(), ext == "m3u8" || ext == "m3u" {
            return true
        }
        return false
    }

    func rewriteM3U8(_ playlist: String, baseURL: URL) -> String {
        playlist.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                return String(line)
            }

            // Drop #EXT-X-PROGRAM-DATE-TIME — Baidu embeds a ~year-2001 timestamp
            // that has broken HLS consumers during our testing.
            if trimmed.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") {
                return ""
            }

            // Directive lines: rewrite URI="..." attributes
            if trimmed.hasPrefix("#") {
                return rewriteURIAttributes(in: String(line), baseURL: baseURL)
            }

            // URL lines: segment or sub-playlist
            let absoluteURL: URL?
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                absoluteURL = URL(string: trimmed)
            } else {
                absoluteURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            }
            if let url = absoluteURL {
                return proxyURL(for: url).absoluteString
            }
            return String(line)
        }.joined(separator: "\n")
    }

    private func rewriteURIAttributes(in line: String, baseURL: URL) -> String {
        guard let range = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) else {
            return line
        }
        let match = String(line[range])
        let urlStart = match.index(match.startIndex, offsetBy: 5)
        let urlEnd = match.index(before: match.endIndex)
        let urlString = String(match[urlStart..<urlEnd])

        let url: URL?
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            url = URL(string: urlString)
        } else {
            url = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }

        guard let url else { return line }
        return line.replacingOccurrences(of: urlString, with: proxyURL(for: url).absoluteString)
    }

    private func register(originalURL: URL) -> String {
        let token = UUID().uuidString
        urlMapLock.lock()
        proxiedURLMap[token] = originalURL
        urlMapLock.unlock()
        return token
    }

    private func tokenOrNil(from request: HTTPRequest, upstreamURL: URL) -> String? {
        if let token = proxyToken(from: request.path) {
            return token
        }
        if let token = request.queryParams["id"] {
            return token
        }
        urlMapLock.lock()
        defer { urlMapLock.unlock() }
        return proxiedURLMap.first(where: { $0.value == upstreamURL })?.key
    }

    private func resolveRegisteredURL(for token: String) -> URL? {
        urlMapLock.lock()
        defer { urlMapLock.unlock() }
        return proxiedURLMap[token]
    }

    private func resolveRegisteredPlaylist(for token: String) -> String? {
        urlMapLock.lock()
        defer { urlMapLock.unlock() }
        return playlistMap[token]
    }

    private func cachedBody(for token: String?) -> PrefetchedBody? {
        guard let token else { return nil }
        urlMapLock.lock()
        defer { urlMapLock.unlock() }
        return prefetchedBodies[token]
    }

    private func storePrefetchedBody(token: String, body: Data, mediaType: String, cacheControl: String) {
        urlMapLock.lock()
        prefetchedBodies[token] = PrefetchedBody(
            token: token,
            body: body,
            mediaType: mediaType,
            cacheControl: cacheControl
        )
        urlMapLock.unlock()
    }

    private func triggerPrefetch(afterServing token: String) {
        guard let next = nextToken(after: token) else { return }
        schedulePrefetch(for: next)
    }

    private func nextToken(after token: String) -> String? {
        urlMapLock.lock()
        defer { urlMapLock.unlock() }
        return nextTokenMap[token]
    }

    private func schedulePrefetch(for token: String) {
        let shouldStart: Bool
        urlMapLock.lock()
        shouldStart = prefetchedBodies[token] == nil && prefetchTasks[token] == nil
        if shouldStart {
            prefetchTasks[token] = Task { [weak self] in
                await self?.prefetch(token: token)
            }
        }
        urlMapLock.unlock()

        if shouldStart {
            NSLog("%@", "[KidsTV][Proxy] Prefetch scheduled \(token)")
        }
    }

    private func prefetch(token: String) async {
        defer {
            urlMapLock.lock()
            prefetchTasks[token] = nil
            urlMapLock.unlock()
        }

        guard let upstreamURL = resolveRegisteredURL(for: token) else { return }

        do {
            var upstream = URLRequest(url: upstreamURL)
            for (key, value) in headers {
                upstream.setValue(value, forHTTPHeaderField: key)
            }

            let (data, response) = try await URLSession.shared.data(for: upstream)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let mediaType = inferredMediaType(for: upstreamURL, response: httpResponse, data: data)
            storePrefetchedBody(
                token: token,
                body: data,
                mediaType: mediaType,
                cacheControl: headerValue("Cache-Control", from: httpResponse) ?? "no-store"
            )
            NSLog("%@", "[KidsTV][Proxy] Prefetched \(token) \(data.count)B \(mediaType)")
        } catch {
            NSLog("%@", "[KidsTV][Proxy] Prefetch failed \(token): \(error.localizedDescription)")
        }
    }

    private func passthroughHeaders(from response: HTTPURLResponse, mediaType: String, bodyLength: Int) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": mediaType,
            "Content-Length": "\(bodyLength)",
            "Accept-Ranges": headerValue("Accept-Ranges", from: response) ?? "bytes"
        ]

        for key in ["Content-Range", "Content-Encoding", "Cache-Control", "ETag", "Last-Modified"] {
            if let value = headerValue(key, from: response) {
                headers[key] = value
            }
        }
        return headers
    }

    private func headerValue(_ key: String, from response: HTTPURLResponse) -> String? {
        for (headerKey, value) in response.allHeaderFields {
            guard let headerName = headerKey as? String,
                  headerName.caseInsensitiveCompare(key) == .orderedSame else { continue }
            return String(describing: value)
        }
        return nil
    }

    private func inferredMediaType(for url: URL, response: HTTPURLResponse, data: Data) -> String {
        if let mime = response.mimeType, mime != "application/octet-stream" {
            return mime
        }
        if looksLikeMP4(data) {
            return "video/mp4"
        }
        if looksLikeMPEGTS(data) {
            return "video/mp2t"
        }
        if url.pathExtension.lowercased() == "aac" {
            return "audio/aac"
        }
        return response.mimeType ?? "application/octet-stream"
    }

    private func looksLikeMPEGTS(_ data: Data) -> Bool {
        guard data.count >= 188 * 3 else { return false }
        return data[0] == 0x47 && data[188] == 0x47 && data[376] == 0x47
    }

    private func looksLikeMP4(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return String(data: data[4..<12], encoding: .ascii)?.hasPrefix("ftyp") == true
    }

    private func hexPrefix(_ data: Data, count: Int) -> String {
        data.prefix(count).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func makeLocalBodyResponse(
        body: Data,
        contentType: String,
        cacheControl: String = "no-store",
        requestRange: String?
    ) -> HTTPResponse {
        let fullLength = body.count
        var headers = [
            "Content-Type": contentType,
            "Accept-Ranges": "bytes",
            "Cache-Control": cacheControl
        ]

        guard let requestRange,
              let parsedRange = parseByteRange(requestRange, fullLength: fullLength) else {
            headers["Content-Length"] = "\(fullLength)"
            return HTTPResponse(status: 200, headers: headers, body: body)
        }

        switch parsedRange {
        case .satisfiable(let lowerBound, let upperBound):
            if lowerBound == 0 && upperBound == fullLength - 1 {
                headers["Content-Length"] = "\(fullLength)"
                return HTTPResponse(status: 200, headers: headers, body: body)
            }
            let subdata = body.subdata(in: lowerBound..<(upperBound + 1))
            headers["Content-Length"] = "\(subdata.count)"
            headers["Content-Range"] = "bytes \(lowerBound)-\(upperBound)/\(fullLength)"
            return HTTPResponse(status: 206, headers: headers, body: subdata)
        case .unsatisfiable:
            headers["Content-Length"] = "0"
            headers["Content-Range"] = "bytes */\(fullLength)"
            return HTTPResponse(status: 416, headers: headers, body: Data())
        }
    }

    private enum ParsedByteRange {
        case satisfiable(lowerBound: Int, upperBound: Int)
        case unsatisfiable
    }

    private func parseByteRange(_ header: String, fullLength: Int) -> ParsedByteRange? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        guard let dashIndex = spec.firstIndex(of: "-") else { return nil }

        let startPart = spec[..<dashIndex].trimmingCharacters(in: .whitespaces)
        let endPart = spec[spec.index(after: dashIndex)...].trimmingCharacters(in: .whitespaces)

        if startPart.isEmpty {
            guard let suffixLength = Int(endPart), suffixLength > 0, fullLength > 0 else {
                return .unsatisfiable
            }
            let clampedLength = min(suffixLength, fullLength)
            return .satisfiable(lowerBound: fullLength - clampedLength, upperBound: fullLength - 1)
        }

        guard let start = Int(startPart), start >= 0, start < fullLength else {
            return .unsatisfiable
        }

        let end = Int(endPart) ?? (fullLength - 1)
        let clampedEnd = min(end, fullLength - 1)
        guard clampedEnd >= start else { return .unsatisfiable }
        return .satisfiable(lowerBound: start, upperBound: clampedEnd)
    }

    private func inferredProxyPathExtension(for url: URL) -> String? {
        let pathExt = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pathExt.isEmpty {
            return pathExt.lowercased()
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let fn = components.queryItems?.first(where: { $0.name == "fn" })?.value {
            let fnExt = (fn as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fnExt.isEmpty {
                return fnExt.lowercased()
            }
        }
        return nil
    }

    private func playlistToken(from path: String) -> String? {
        guard path.hasPrefix("/playlist/") else { return nil }
        let tokenWithExt = String(path.dropFirst("/playlist/".count))
        return tokenWithExt.replacingOccurrences(of: ".m3u8", with: "")
    }

    private func proxyToken(from path: String) -> String? {
        guard path.hasPrefix("/proxy/") else { return nil }
        let tail = String(path.dropFirst("/proxy/".count))
        guard !tail.isEmpty else { return nil }
        return tail.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

}

private struct PrefetchedBody {
    let token: String
    let body: Data
    let mediaType: String
    let cacheControl: String
}

// MARK: - Minimal HTTP Server (no external dependencies)

/// Simple HTTP/1.1 server using Foundation sockets.
private final class HTTPServer {
    let port: UInt16
    private var listeningSocket: Int32 = -1
    private let handler: (HTTPRequest) async -> HTTPResponse
    private var isRunning = false

    init(handler: @escaping (HTTPRequest) async -> HTTPResponse) {
        self.handler = handler

        // Create socket
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to any available port
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // OS assigns port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bindAddr in
                bind(sock, bindAddr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Get assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                getsockname(sock, sockAddr, &addrLen)
            }
        }

        self.listeningSocket = sock
        self.port = UInt16(bigEndian: assignedAddr.sin_port)

        // Listen
        listen(sock, 32)
        isRunning = true

        // Accept loop on background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if listeningSocket >= 0 {
            Darwin.close(listeningSocket)
            listeningSocket = -1
        }
    }

    deinit {
        stop()
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                    accept(listeningSocket, sockAddr, &clientLen)
                }
            }
            guard clientSocket >= 0, isRunning else { continue }

            Task {
                await self.handleConnection(clientSocket)
            }
        }
    }

    private func handleConnection(_ socket: Int32) async {
        defer { Darwin.close(socket) }

        // Read request — use 32KB buffer for long URLs
        var buffer = [UInt8](repeating: 0, count: 32768)
        let bytesRead = recv(socket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let requestData = Data(buffer[0..<bytesRead])
        if let requestPreview = String(data: requestData.prefix(200), encoding: .utf8) {
            let oneLine = requestPreview.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
            NSLog("%@", "[KidsTV][Proxy] Accepted \(bytesRead)B: \(oneLine)")
        } else {
            NSLog("%@", "[KidsTV][Proxy] Accepted \(bytesRead)B (non-utf8 preview)")
        }
        guard let requestString = String(data: requestData, encoding: .utf8),
              let request = HTTPRequest.parse(requestString) else {
            NSLog("%@", "[KidsTV][Proxy] Failed to parse request (\(bytesRead)B)")
            return
        }

        // Handle
        let response = await handler(request)
        NSLog("%@", "[KidsTV][Proxy] Responding \(response.status) to \(request.method) \(request.path) headers=\(response.headers)")

        // Build response header
        var header = "HTTP/1.1 \(response.status) \(response.statusText)\r\n"
        header += "Connection: close\r\n"
        for (key, value) in response.headers {
            header += "\(key): \(value)\r\n"
        }
        if response.headers["Content-Length"] == nil {
            header += "Content-Length: \(response.body.count)\r\n"
        }
        header += "\r\n"

        // Send header
        sendAll(socket: socket, data: Data(header.utf8))
        // Send body
        sendAll(socket: socket, data: response.body)
    }

    /// Send all bytes, handling partial writes.
    private func sendAll(socket: Int32, data: Data) {
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = send(socket, base.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let queryParams: [String: String]
    let headers: [String: String]

    static func parse(_ raw: String) -> HTTPRequest? {
        let lines = raw.split(separator: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let fullPath = String(parts[1])

        // Parse headers
        var hdrs: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            hdrs[key] = value
        }

        guard let components = URLComponents(string: fullPath) else {
            return HTTPRequest(method: method, path: fullPath, queryParams: [:], headers: hdrs)
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value
        }

        return HTTPRequest(method: method, path: components.path, queryParams: params, headers: hdrs)
    }
}

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    var statusText: String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        default: return "Unknown"
        }
    }

    init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}
