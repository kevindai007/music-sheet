import MusicSheetKit
import SwiftUI

/// Picks a style and asks the AI to re-chord the current sheet. The result is saved as a new song.
struct RearrangeView: View {
    let sheet: SongSheet
    var onRearranged: (SongSheet) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @State private var selected: ArrangementStyle?
    @State private var custom = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    /// The text sent to the backend: the custom description wins over a preset.
    private var style: String {
        let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? selected?.prompt ?? "" : text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ArrangementStyle.presets) { preset in
                        Button {
                            selected = preset
                            custom = ""
                        } label: {
                            HStack {
                                Label(preset.name, systemImage: preset.symbol)
                                Spacer()
                                if selected == preset && custom.isEmpty {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("选一个风格")
                }
                Section {
                    TextField("例如：像周杰伦《晴天》那样的编曲，副歌加一点 R&B 味道", text: $custom, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("或者自己描述")
                } footer: {
                    Text("歌词和段落保持不变，只改和弦、节奏型，必要时会换调。改编版会作为一首新曲谱保存，原版不受影响。")
                }
                if isWorking {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在改编，大约需要半分钟到一分钟…").foregroundStyle(.secondary)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("AI 改编《\(sheet.title)》")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        task?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("改编", action: rearrange).disabled(style.isEmpty || isWorking)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func rearrange() {
        errorMessage = nil
        isWorking = true
        // Store the short preset name when one was picked, so the library badge stays readable.
        let label = custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selected?.name : nil
        let prompt = style
        task = Task {
            defer { isWorking = false }
            do {
                var result = try await auth.makeClient().rearrange(sheet, style: prompt)
                if let label { result.arrangement = .init(style: label) }
                onRearranged(result)
                dismiss()
            } catch is CancellationError {
                // The user cancelled.
            } catch let error as URLError where error.code == .cancelled {
                // The user cancelled.
            } catch {
                auth.handle(error)
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A small capsule naming an arrangement's style.
struct ArrangementBadge: View {
    let style: String

    var body: some View {
        Text(style)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: .capsule)
            .foregroundStyle(Color.accentColor)
    }
}
