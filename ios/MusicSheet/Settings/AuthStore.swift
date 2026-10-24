import Foundation
import MusicSheetKit
import Observation

/// Who the app talks to the backend as: a signed-in user, or (Debug builds) the developer token.
@MainActor @Observable
final class AuthStore {
    private static let emailKey = "accountEmail"

    private(set) var sessionToken: String? = Keychain.session
    private(set) var email: String? = UserDefaults.standard.string(forKey: emailKey)

    var isSignedIn: Bool { sessionToken != nil }

    /// A signed-in session wins over the developer token.
    var credential: APIClient.Credential? {
        if let sessionToken { return .session(sessionToken) }
        if let token = AppSettings.appToken { return .appToken(token) }
        return nil
    }

    var canUseAPI: Bool { credential != nil }

    func makeClient() throws -> APIClient {
        guard let credential else { throw AppSettings.ConfigurationError.notSignedIn }
        return APIClient(baseURL: try AppSettings.baseURL(), credential: credential)
    }

    func signIn(_ provider: APIClient.IdentityProvider, idToken: String) async throws {
        let client = APIClient(baseURL: try AppSettings.baseURL(), credential: nil)
        let result = try await client.signIn(provider: provider, idToken: idToken)
        Keychain.session = result.sessionToken
        sessionToken = result.sessionToken
        email = result.user.email
        UserDefaults.standard.set(result.user.email, forKey: Self.emailKey)
    }

    func signOut() {
        Keychain.session = nil
        sessionToken = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
    }

    func deleteAccount() async throws {
        try await makeClient().deleteAccount()
        signOut()
    }

    /// Call with any error from the backend: an expired session signs the user out so they are asked again.
    func handle(_ error: Error) {
        if isSignedIn, (error as? APIClient.APIError) == .unauthorized { signOut() }
    }
}
