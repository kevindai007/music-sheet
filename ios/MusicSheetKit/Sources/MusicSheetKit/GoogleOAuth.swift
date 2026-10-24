import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Google sign-in for an iOS OAuth client, without the Google SDK: the authorization-code flow with PKCE.
/// The app opens `authorizationURL` in a web authentication session, then trades the returned code for an ID token.
public struct GoogleOAuth: Sendable {
    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID
    }

    /// iOS clients redirect to the client id reversed, e.g. `com.googleusercontent.apps.123-abc`.
    public var callbackScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public var redirectURI: String { "\(callbackScheme):/oauthredirect" }

    public func authorizationURL(state: String, codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    public enum OAuthError: LocalizedError, Equatable {
        case cancelled
        case denied(String)
        case invalidCallback

        public var errorDescription: String? {
            switch self {
            case .cancelled: "已取消登录。"
            case .denied(let reason): "Google 拒绝了登录（\(reason)）。"
            case .invalidCallback: "Google 登录返回的数据无法识别。"
            }
        }
    }

    /// Pulls the authorization code out of the redirect, checking it answers our request.
    public func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw error == "access_denied" ? OAuthError.cancelled : OAuthError.denied(error) }
        guard value("state") == expectedState, let code = value("code"), !code.isEmpty else { throw OAuthError.invalidCallback }
        return code
    }

    public func tokenRequest(code: String, codeVerifier: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectURI),
        ]
        // URLComponents leaves "+" and "/" alone, but a form body must escape everything but the unreserved set.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
        request.httpBody = Data(body.joined(separator: "&").utf8)
        return request
    }

    /// Exchanges the code for Google's ID token, which the backend verifies.
    public func idToken(code: String, codeVerifier: String, session: URLSession = .shared) async throws -> String {
        struct TokenResponse: Decodable { var id_token: String }
        let (data, response) = try await session.data(for: tokenRequest(code: code, codeVerifier: codeVerifier))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw OAuthError.invalidCallback
        }
        return token.id_token
    }

    /// A random URL-safe string, used for both the PKCE verifier and `state`.
    public static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    #if canImport(CryptoKit)
    public static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    #endif

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
