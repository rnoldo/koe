import Foundation

enum ScannerError: LocalizedError {
    case missingConfig(String)
    case invalidURL
    case authRequired
    case tokenExpired
    case notImplemented(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig(let msg): return "Missing config: \(msg)"
        case .invalidURL: return "Invalid URL"
        case .authRequired: return "Authentication required — please sign in"
        case .tokenExpired: return "Token expired — please re-authenticate"
        case .notImplemented(let name): return "\(name) is not yet implemented"
        case .serverError(let msg): return msg
        }
    }
}
