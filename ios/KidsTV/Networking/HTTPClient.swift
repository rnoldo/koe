import Foundation

enum HTTPError: LocalizedError {
    case badStatus(Int, Data)
    case invalidResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, _): return "HTTP \(code)"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Unauthorized — check credentials"
        }
    }
}

struct HTTPClient {

    static let shared = HTTPClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Core

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        if http.statusCode == 401 { throw HTTPError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.badStatus(http.statusCode, data)
        }
        return (data, http)
    }

    // MARK: - Convenience

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await data(for: req)
    }

    func post(_ url: URL, body: Data?, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await data(for: req)
    }

    func postForm(_ url: URL, params: [String: String], headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let body = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await data(for: req)
    }

    /// Send a custom HTTP method (e.g., PROPFIND for WebDAV)
    func send(method: String, url: URL, body: Data? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await data(for: req)
    }

    // MARK: - Auth Helpers

    static func basicAuthHeader(username: String, password: String) -> String {
        let cred = "\(username):\(password)"
        let encoded = Data(cred.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
