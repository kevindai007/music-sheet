import AuthenticationServices
import MusicSheetKit
import SwiftUI

/// Shows `content` once the app can call the backend, and the sign-in screen until then.
struct SignInGate<Content: View>: View {
    @Environment(AuthStore.self) private var auth
    @ViewBuilder var content: () -> Content

    var body: some View {
        if auth.canUseAPI {
            content()
        } else {
            NavigationStack { SignInView() }
        }
    }
}

struct SignInView: View {
    /// When shown on its own (from Settings), close after signing in. Inside a `SignInGate` the content takes over instead.
    var dismissOnSuccess = false

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var hasProvider: Bool { AppSettings.appleSignInEnabled || AppSettings.googleClientID != nil }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("登录后使用 AI 生成和改编")
                .font(.title2.bold())
            Text("登录只用来识别你的身份和统计每天的使用次数，不会获取其他信息。已保存的曲谱不登录也能看。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            if AppSettings.appleSignInEnabled {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    Task { await finishApple(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
            }
            if let clientID = AppSettings.googleClientID {
                Button {
                    Task { await signInWithGoogle(GoogleOAuth(clientID: clientID)) }
                } label: {
                    Label("使用 Google 登录", systemImage: "g.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
            if !hasProvider {
                Text("这个版本还没有开启登录。")
                    .foregroundStyle(.secondary)
            }
            if isWorking { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .disabled(isWorking)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let idToken = String(data: data, encoding: .utf8) else {
                errorMessage = "Apple 没有返回登录凭证，请重试。"
                return
            }
            await signIn(.apple) { idToken }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle(_ google: GoogleOAuth) async {
        await signIn(.google) {
            let verifier = GoogleOAuth.randomToken()
            let state = GoogleOAuth.randomToken()
            let callback = try await webAuthenticationSession.authenticate(
                using: google.authorizationURL(state: state, codeChallenge: GoogleOAuth.codeChallenge(for: verifier)),
                callbackURLScheme: google.callbackScheme,
                preferredBrowserSession: .shared
            )
            let code = try google.code(fromCallback: callback, expectedState: state)
            return try await google.idToken(code: code, codeVerifier: verifier)
        }
    }

    /// Gets an identity token from Apple/Google, then trades it for our own session.
    private func signIn(_ provider: APIClient.IdentityProvider, idToken: () async throws -> String) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signIn(provider, idToken: try await idToken())
            if dismissOnSuccess { dismiss() }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the Google page.
        } catch GoogleOAuth.OAuthError.cancelled {
            // The user declined on the Google page.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
