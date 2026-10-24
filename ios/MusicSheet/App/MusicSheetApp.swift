import SwiftData
import SwiftUI

@main
struct MusicSheetApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(auth)
        }
        .modelContainer(for: SavedSong.self)
    }
}
