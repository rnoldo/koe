import Foundation
import AuthenticationServices

@MainActor
class OAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = OAuthManager()

    /// Launch OAuth2 flow and return the authorization code
    func authenticate(authURL: URL, callbackScheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: ScannerError.authRequired)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// Exchange authorization code for access + refresh tokens
    func exchangeToken(
        tokenURL: URL,
        code: String,
        clientId: String,
        clientSecret: String?,
        redirectURI: String
    ) async throws -> OAuthTokens {
        var params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
        ]
        if let secret = clientSecret { params["client_secret"] = secret }

        let (data, _) = try await HTTPClient.shared.postForm(tokenURL, params: params)
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        return OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresIn: response.expires_in
        )
    }

    /// Refresh an expired access token
    func refreshToken(
        tokenURL: URL,
        refreshToken: String,
        clientId: String,
        clientSecret: String?
    ) async throws -> OAuthTokens {
        var params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ]
        if let secret = clientSecret { params["client_secret"] = secret }

        let (data, _) = try await HTTPClient.shared.postForm(tokenURL, params: params)
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        return OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? refreshToken,
            expiresIn: response.expires_in
        )
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

struct OAuthTokens {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

private struct OAuthTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
}
