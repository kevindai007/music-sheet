import MusicSheetKit
import SwiftUI

struct GenerateSongView: View {
    var onGenerated: (SongSheet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("歌名", text: $title)
                    TextField("歌手（可选，填了更准）", text: $artist)
                }
                if isWorking {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在获取歌词并配和弦，大约需要半分钟到一分钟…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("生成曲谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        task?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成", action: generate)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func generate() {
        errorMessage = nil
        isWorking = true
        task = Task {
            defer { isWorking = false }
            do {
                let client = try AppSettings.makeClient()
                let sheet = try await client.generateSong(
                    title: title.trimmingCharacters(in: .whitespaces),
                    artist: artist.trimmingCharacters(in: .whitespaces)
                )
                onGenerated(sheet)
                dismiss()
            } catch is CancellationError {
                // The user cancelled.
            } catch let error as URLError where error.code == .cancelled {
                // The user cancelled.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
