import Foundation
import MusicSheetKit
import Security

/// Where the backend lives. The URL is a plain preference; the token is kept in the Keychain.
enum AppSettings {
    static let backendURLKey = "backendURL"
    /// The deployed backend. For local development use `http://localhost:8787` (Simulator) or your Mac's LAN address.
    static let defaultBackendURL = "https://app.kevinonline.org"

    static var backendURL: String {
        UserDefaults.standard.string(forKey: backendURLKey) ?? defaultBackendURL
    }

    static func makeClient() throws -> APIClient {
        guard let url = URL(string: backendURL.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            throw ConfigurationError.invalidURL
        }
        guard let token = Keychain.appToken, !token.isEmpty else { throw ConfigurationError.missingToken }
        return APIClient(baseURL: url, token: token)
    }

    enum ConfigurationError: LocalizedError {
        case invalidURL, missingToken

        var errorDescription: String? {
            switch self {
            case .invalidURL: "后端地址无效，请在设置里检查。"
            case .missingToken: "还没有填写 App Token，请先到设置里填写。"
            }
        }
    }
}

enum Keychain {
    private static let service = "com.kevindai.musicsheet"
    private static let account = "appToken"

    static var appToken: String? {
        get {
            var item: CFTypeRef?
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = query
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
