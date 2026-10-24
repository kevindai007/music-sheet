import MusicSheetKit
import SwiftUI

/// Edits the chords of one line. Chords are entered in the song's original key.
struct LineEditorView: View {
    let key: String
    var onSave: (SongSheet.Line) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var line: SongSheet.Line

    init(line: SongSheet.Line, key: String, onSave: @escaping (SongSheet.Line) -> Void) {
        self.key = key
        self.onSave = onSave
        _line = State(initialValue: line)
    }

    private var characters: [Character] { Array(line.text) }

    var body: some View {
        NavigationStack {
            Form {
                Section("预览") {
                    LyricLineView(line: line, formatChord: { $0 })
                }
                Section {
                    ForEach(line.chords.indices, id: \.self) { i in
                        HStack {
                            TextField("和弦", text: $line.chords[i].chord)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(width: 80)
                                .foregroundStyle(Chord(line.chords[i].chord) == nil ? Color.red : Color.primary)
                            Stepper(value: $line.chords[i].at, in: 0...max(characters.count - 1, 0)) {
                                Text("在「\(characters.indices.contains(line.chords[i].at) ? String(characters[line.chords[i].at]) : "")」上")
                            }
                        }
                    }
                    .onDelete { line.chords.remove(atOffsets: $0) }
                    Button("添加和弦", systemImage: "plus") {
                        line.chords.append(.init(at: line.chords.last.map { min($0.at + 1, max(characters.count - 1, 0)) } ?? 0, chord: ""))
                    }
                } header: {
                    Text("和弦")
                } footer: {
                    Text("按原调 \(key) 填写，例如 C、Am7、G/B。左滑删除。")
                }
            }
            .navigationTitle(line.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var cleaned = line
                        cleaned.chords = line.chords
                            .map { .init(at: $0.at, chord: $0.chord.trimmingCharacters(in: .whitespaces)) }
                            .filter { !$0.chord.isEmpty }
                            .sorted { $0.at < $1.at }
                        onSave(cleaned)
                        dismiss()
                    }
                    .disabled(line.chords.contains { !$0.chord.trimmingCharacters(in: .whitespaces).isEmpty && Chord($0.chord) == nil })
                }
            }
        }
    }
}
