import Foundation
import MusicSheetKit
import Security

/// Where the backend lives. Both the URL and the token work out of the box; Settings can override them for debugging.
/// The URL override is a plain preference, the token override is kept in the Keychain.
enum AppSettings {
    static let backendURLKey = "backendURL"
    /// The deployed backend. For local development use `http://localhost:8787` (Simulator) or your Mac's LAN address.
    static let defaultBackendURL = "https://app.kevinonline.org"

    /// The override from Settings, or the deployed backend when there is none.
    static var backendURL: String {
        let override = UserDefaults.standard.string(forKey: backendURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return override.isEmpty ? defaultBackendURL : override
    }

    /// The token baked in at build time from `Secrets.xcconfig` (see `ios/setup.sh`).
    static var bundledToken: String? {
        let token = Bundle.main.object(forInfoDictionaryKey: "MusicSheetAppToken") as? String
        return token?.isEmpty == false ? token : nil
    }

    /// The token typed in Settings, or the bundled one.
    static var appToken: String? {
        if let token = Keychain.appToken, !token.isEmpty { return token }
        return bundledToken
    }

    static func makeClient() throws -> APIClient {
        guard let url = URL(string: backendURL.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            throw ConfigurationError.invalidURL
        }
        guard let token = appToken else { throw ConfigurationError.missingToken }
        return APIClient(baseURL: url, token: token)
    }

    enum ConfigurationError: LocalizedError {
        case invalidURL, missingToken

        var errorDescription: String? {
            switch self {
            case .invalidURL: "后端地址无效，请在设置里检查。"
            case .missingToken: "这个版本没有内置 App Token：在 Mac 上运行 ios/setup.sh 重新安装，或到设置里填写。"
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
