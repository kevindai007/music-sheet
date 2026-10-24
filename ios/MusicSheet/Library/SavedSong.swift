import Foundation
import MusicSheetKit
import SwiftData

/// A song sheet in the user's library, with their per-song display settings.
@Model
final class SavedSong {
    var id: UUID
    var title: String
    var artist: String
    var createdAt: Date
    var updatedAt: Date
    /// JSON-encoded `SongSheet`, kept as one blob so the schema can evolve with the backend.
    var sheetData: Data
    /// Semitones the song is shifted from the original key.
    var transpose: Int
    var capo: Int
    /// The style of an AI rearrangement; nil for the original arrangement.
    var arrangementStyle: String?

    init(sheet: SongSheet) {
        id = UUID()
        title = sheet.title
        artist = sheet.artist
        createdAt = .now
        updatedAt = .now
        sheetData = (try? JSONEncoder().encode(sheet)) ?? Data()
        transpose = 0
        capo = sheet.capo
        arrangementStyle = sheet.arrangement?.style
    }

    var sheet: SongSheet? {
        try? JSONDecoder().decode(SongSheet.self, from: sheetData)
    }

    func update(_ sheet: SongSheet) {
        guard let data = try? JSONEncoder().encode(sheet) else { return }
        sheetData = data
        title = sheet.title
        artist = sheet.artist
        updatedAt = .now
    }
}
