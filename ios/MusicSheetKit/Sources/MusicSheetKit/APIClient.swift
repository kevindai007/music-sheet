import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the music-sheet backend (see `backend/README.md`).
public struct APIClient: Sendable {
    public var baseURL: URL
    public var token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public enum APIError: LocalizedError, Equatable {
        case unauthorized
        case lyricsNotFound(String)
        case server(status: Int, message: String?)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .unauthorized: "App Token 不正确，请在设置里检查。"
            case .lyricsNotFound(let message): message
            case .server(let status, let message): message ?? "服务器出错（HTTP \(status)）。"
            case .invalidResponse: "服务器返回的数据无法识别。"
            }
        }
    }

    /// Fetches lyrics and has Claude add chords. Usually takes 20–60 seconds.
    public func generateSong(title: String, artist: String?) async throws -> SongSheet {
        var request = URLRequest(url: baseURL.appendingPathComponent("songs/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-App-Token")
        var body = ["title": title]
        if let artist, !artist.isEmpty { body["artist"] = artist }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return try Self.decodeGenerateResponse(status: http.statusCode, data: data)
    }

    static func decodeGenerateResponse(status: Int, data: Data) throws -> SongSheet {
        struct ErrorBody: Decodable { var error: String; var message: String? }
        switch status {
        case 200:
            do { return try JSONDecoder().decode(SongSheet.self, from: data) } catch { throw APIError.invalidResponse }
        case 401:
            throw APIError.unauthorized
        default:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if status == 404, body?.error == "lyrics_not_found" {
                throw APIError.lyricsNotFound(body?.message ?? "没有找到这首歌的歌词。")
            }
            throw APIError.server(status: status, message: body?.message)
        }
    }
}
