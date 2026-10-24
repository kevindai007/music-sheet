import MusicSheetKit
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSong.updatedAt, order: .reverse) private var songs: [SavedSong]
    @State private var path: [SavedSong] = []
    @State private var search = ""
    @State private var showingGenerate = false
    @State private var showingSettings = false

    private var filtered: [SavedSong] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return songs }
        return songs.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("曲库是空的", systemImage: "music.note.list")
                    } description: {
                        Text("输入歌名，自动获取歌词并配好和弦。")
                    } actions: {
                        Button("生成曲谱") { showingGenerate = true }
                            .buttonStyle(.borderedProminent)
                        Button("载入示例《小星星》") { open(SavedSong(sheet: SampleSongs.twinkle)) }
                    }
                } else {
                    List {
                        ForEach(filtered) { song in
                            NavigationLink(value: song) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(song.title).font(.headline)
                                        if let style = song.arrangementStyle {
                                            ArrangementBadge(style: style)
                                        }
                                    }
                                    Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(filtered[i]) }
                        }
                    }
                    .searchable(text: $search, prompt: "搜索歌名或歌手")
                }
            }
            .navigationTitle("曲库")
            .navigationDestination(for: SavedSong.self) { SongSheetView(song: $0, onOpen: open) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingGenerate = true } label: { Label("生成曲谱", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingGenerate) {
                GenerateSongView { open(SavedSong(sheet: $0)) }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    /// Saves a new song and shows it on top of whatever is open.
    private func open(_ song: SavedSong) {
        modelContext.insert(song)
        path.append(song)
    }
}
