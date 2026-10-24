import MusicSheetKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    /// Empty means "use the deployed backend".
    @AppStorage(AppSettings.backendURLKey) private var backendURL = ""
    @State private var token = Keychain.appToken ?? ""
    @State private var showingAdvanced = false
    @State private var showingSignIn = false
    @State private var confirmingDelete = false
    @State private var account: APIClient.Account?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if auth.isSignedIn {
                        LabeledContent("已登录", value: auth.email ?? "（未提供邮箱）")
                        if let usage = account?.usage, let limit = usage.limit {
                            LabeledContent("今日 AI 次数", value: "\(usage.used) / \(limit)")
                        }
                        Button("退出登录") { auth.signOut() }
                        Button("删除账号", role: .destructive) { confirmingDelete = true }
                    } else {
                        Button("登录") { showingSignIn = true }
                        if AppSettings.appToken != nil {
                            Text("当前使用开发者 Token，不限次数。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                } header: {
                    Text("账号")
                }

                Section {
                    DisclosureGroup("调试设置", isExpanded: $showingAdvanced) {
                        LabeledContent("服务器", value: AppSettings.backendURL)
                        TextField(AppSettings.defaultBackendURL, text: $backendURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField(AppSettings.bundledToken == nil ? "开发者 Token" : "开发者 Token（留空用内置的）", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !backendURL.isEmpty || !token.isEmpty {
                            Button("恢复默认", role: .destructive) {
                                backendURL = ""
                                token = ""
                            }
                        }
                    }
                } footer: {
                    Text("平时不用改。本地调试时，模拟器填 http://localhost:8787，真机填 Mac 的局域网地址（如 http://192.168.1.10:8787，后端用 npm run dev:lan 启动）。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        backendURL = backendURL.trimmingCharacters(in: .whitespaces)
                        Keychain.appToken = token.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSignIn) {
                NavigationStack { SignInView(dismissOnSuccess: true) }
            }
            .confirmationDialog("删除账号？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除账号", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("服务器上只保存了你的使用次数，会一并删除。手机上的曲谱不受影响。")
            }
            .task(id: auth.sessionToken) { await loadAccount() }
            .onAppear {
                // Older versions stored the default URL itself; treat that as "no override".
                if backendURL == AppSettings.defaultBackendURL { backendURL = "" }
                showingAdvanced = !backendURL.isEmpty
            }
        }
    }

    private func loadAccount() async {
        account = nil
        guard auth.isSignedIn else { return }
        do {
            account = try await auth.makeClient().account()
        } catch {
            auth.handle(error)
        }
    }

    private func deleteAccount() async {
        errorMessage = nil
        do {
            try await auth.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
