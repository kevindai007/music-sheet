import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Empty means "use the deployed backend".
    @AppStorage(AppSettings.backendURLKey) private var backendURL = ""
    @State private var token = Keychain.appToken ?? ""
    @State private var showingAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section("后端") {
                    LabeledContent("服务器", value: AppSettings.backendURL)
                    LabeledContent("App Token", value: tokenStatus)
                }

                Section {
                    DisclosureGroup("调试设置", isExpanded: $showingAdvanced) {
                        TextField(AppSettings.defaultBackendURL, text: $backendURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField(AppSettings.bundledToken == nil ? "App Token" : "App Token（留空用内置的）", text: $token)
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
            .onAppear {
                // Older versions stored the default URL itself; treat that as "no override".
                if backendURL == AppSettings.defaultBackendURL { backendURL = "" }
                showingAdvanced = !backendURL.isEmpty || AppSettings.appToken == nil
            }
        }
    }

    private var tokenStatus: String {
        if let typed = Keychain.appToken, !typed.isEmpty { return "已手动填写" }
        return AppSettings.bundledToken == nil ? "未设置" : "已内置"
    }
}
