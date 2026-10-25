import SwiftData
import SwiftUI

@main
struct MusicSheetApp: App {
    @State private var auth = AuthStore()
    @State private var guitar = GuitarConnection()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(auth)
                .environment(guitar)
        }
        .modelContainer(for: SavedSong.self)
    }
}
