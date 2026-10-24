import Foundation
import MusicSheetKit
import Security

/// Where the backend lives and which sign-in methods this build offers. Values marked "build" come from
/// `Config.xcconfig` / `Secrets.xcconfig` through Info.plist; Settings can override the URL and token for debugging.
enum AppSettings {
    static let backendURLKey = "backendURL"
    /// The deployed backend. For local development use `http://localhost:8787` (Simulator) or your Mac's LAN address.
    static let defaultBackendURL = "https://app.kevinonline.org"

    /// The override from Settings, or the deployed backend when there is none.
    static var backendURL: String {
        let override = UserDefaults.standard.string(forKey: backendURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return override.isEmpty ? defaultBackendURL : override
    }

    static func baseURL() throws -> URL {
        guard let url = URL(string: backendURL), url.scheme != nil else { throw ConfigurationError.invalidURL }
        return url
    }

    /// Build: the developer token, only in Debug builds (see `Config.xcconfig`).
    static var bundledToken: String? { infoString("MusicSheetAppToken") }

    /// The developer token typed in Settings, or the bundled one.
    static var appToken: String? {
        if let token = Keychain.appToken, !token.isEmpty { return token }
        return bundledToken
    }

    /// Build: Google iOS OAuth client id; Google sign-in is hidden without it.
    static var googleClientID: String? { infoString("MusicSheetGoogleClientID") }

    /// Build: Sign in with Apple needs a paid developer account, so it is switched on in `Config.xcconfig`.
    static var appleSignInEnabled: Bool { infoString("MusicSheetAppleSignIn") == "YES" }

    private static func infoString(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    enum ConfigurationError: LocalizedError {
        case invalidURL, notSignedIn

        var errorDescription: String? {
            switch self {
            case .invalidURL: "后端地址无效，请在设置里检查。"
            case .notSignedIn: "请先登录。"
            }
        }
    }
}

/// Generic-password items in the Keychain.
enum Keychain {
    private static let service = "com.kevindai.musicsheet"

    /// Developer token typed in Settings.
    static var appToken: String? {
        get { read("appToken") }
        set { write("appToken", newValue) }
    }

    /// Session token from Apple/Google sign-in.
    static var session: String? {
        get { read("session") }
        set { write("session", newValue) }
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> String? {
        var item: CFTypeRef?
        var query = query(account)
        query[kSecReturnData as String] = true
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query(account)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
