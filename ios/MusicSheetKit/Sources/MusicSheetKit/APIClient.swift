import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the music-sheet backend (see `backend/README.md`).
public struct APIClient: Sendable {
    /// How a request proves who is calling.
    public enum Credential: Sendable, Equatable {
        /// The session token from `signIn`, sent as a Bearer token.
        case session(String)
        /// The developer token (`APP_TOKEN` on the server), which has no daily limit.
        case appToken(String)
    }

    public var baseURL: URL
    public var credential: Credential?
    private let session: URLSession

    public init(baseURL: URL, credential: Credential?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credential = credential
        self.session = session
    }

    public enum APIError: LocalizedError, Equatable {
        case unauthorized
        case lyricsNotFound(String)
        case quotaExceeded(String)
        case server(status: Int, message: String?)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .unauthorized: "请先登录，或登录已过期。"
            case .lyricsNotFound(let message), .quotaExceeded(let message): message
            case .server(let status, let message): message ?? "服务器出错（HTTP \(status)）。"
            case .invalidResponse: "服务器返回的数据无法识别。"
            }
        }
    }

    public enum IdentityProvider: String, Codable, Sendable {
        case apple, google
    }

    public struct User: Codable, Sendable, Equatable {
        public var id: String
        public var email: String?
    }

    public struct SignInResult: Codable, Sendable, Equatable {
        public var sessionToken: String
        public var expiresAt: String
        public var user: User
    }

    public struct Account: Codable, Sendable, Equatable {
        public struct Usage: Codable, Sendable, Equatable {
            public var used: Int
            /// `nil` for the developer token, which is not limited.
            public var limit: Int?
        }

        public var user: User?
        public var owner: Bool
        public var usage: Usage
    }

    /// Exchanges an Apple or Google identity token for a session token.
    public func signIn(provider: IdentityProvider, idToken: String) async throws -> SignInResult {
        try await send("POST", "auth/signin", body: ["provider": provider.rawValue, "idToken": idToken])
    }

    /// The signed-in user and today's usage.
    public func account() async throws -> Account {
        try await send("GET", "auth/me")
    }

    /// Deletes the account on the server (it only keeps usage counts).
    public func deleteAccount() async throws {
        struct OK: Decodable { var ok: Bool }
        _ = try await send("DELETE", "auth/account") as OK
    }

    /// Fetches lyrics and has the AI add chords. Usually takes 20–60 seconds.
    public func generateSong(title: String, artist: String?) async throws -> SongSheet {
        var body = ["title": title]
        if let artist, !artist.isEmpty { body["artist"] = artist }
        return try await send("POST", "songs/generate", body: body)
    }

    /// Asks the AI to re-chord `sheet` in `style`. Lyrics and sections stay the same.
    public func rearrange(_ sheet: SongSheet, style: String) async throws -> SongSheet {
        struct Body: Encodable { var sheet: SongSheet; var style: String }
        return try await send("POST", "songs/rearrange", body: Body(sheet: sheet, style: style))
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 180
        switch credential {
        case .session(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .appToken(let token): request.setValue(token, forHTTPHeaderField: "X-App-Token")
        case nil: break
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return try Self.decodeResponse(status: http.statusCode, data: data)
    }

    static func decodeSheetResponse(status: Int, data: Data) throws -> SongSheet {
        try decodeResponse(status: status, data: data)
    }

    static func decodeResponse<T: Decodable>(status: Int, data: Data) throws -> T {
        struct ErrorBody: Decodable { var error: String; var message: String? }
        switch status {
        case 200:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw APIError.invalidResponse }
        case 401:
            throw APIError.unauthorized
        default:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if status == 404, body?.error == "lyrics_not_found" {
                throw APIError.lyricsNotFound(body?.message ?? "没有找到这首歌的歌词。")
            }
            if status == 429, body?.error == "quota_exceeded" {
                throw APIError.quotaExceeded(body?.message ?? "今天的次数已经用完了。")
            }
            throw APIError.server(status: status, message: body?.message)
        }
    }
}
