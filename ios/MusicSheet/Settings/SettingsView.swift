import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.backendURLKey) private var backendURL = AppSettings.defaultBackendURL
    @State private var token = Keychain.appToken ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("后端地址", text: $backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("App Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("后端")
                } footer: {
                    Text("默认连接部署在服务器上的 https://app.kevinonline.org。本地调试时，模拟器填 http://localhost:8787，真机填 Mac 的局域网地址（如 http://192.168.1.10:8787，后端用 npm run dev:lan 启动）。App Token 要和后端的 APP_TOKEN 一致。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Keychain.appToken = token.trimmingCharacters(in: .whitespaces)
                        dismiss()
                    }
                }
            }
        }
    }
}
