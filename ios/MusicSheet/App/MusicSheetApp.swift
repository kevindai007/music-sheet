import SwiftData
import SwiftUI

@main
struct MusicSheetApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: SavedSong.self)
    }
}
