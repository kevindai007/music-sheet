import Foundation

/// A musical key such as "G" or "Em".
public struct MusicalKey: Hashable, Sendable {
    public var tonic: PitchClass
    public var isMinor: Bool

    public init(tonic: PitchClass, isMinor: Bool) {
        self.tonic = tonic
        self.isMinor = isMinor
    }

    public init?(_ name: String) {
        guard let chord = Chord(name) else { return nil }
        self.init(tonic: chord.root, isMinor: chord.isMinor)
    }

    /// Tonic of the major key that shares this key's notes (C for Am).
    public var relativeMajorTonic: PitchClass {
        isMinor ? tonic.transposed(by: 3) : tonic
    }

    /// Whether chord names in this key read better with flats (F, Bb, Eb, Ab, Db and their relative minors; F# over Gb).
    public var prefersFlats: Bool {
        [5, 10, 3, 8, 1].contains(relativeMajorTonic.value)
    }

    public func transposed(by semitones: Int) -> MusicalKey {
        MusicalKey(tonic: tonic.transposed(by: semitones), isMinor: isMinor)
    }

    public var name: String {
        tonic.name(preferFlats: prefersFlats) + (isMinor ? "m" : "")
    }
}

/// How chords are shown on the sheet.
public enum ChordNotation: String, CaseIterable, Sendable {
    /// Letter names, e.g. "Am7".
    case letters
    /// Scale degrees relative to the major key, e.g. "6m7". Matches LiberLive's numbered chord buttons.
    case degrees
}

public enum ChordFormatter {
    private static let degreeNames: [Int: String] = [
        0: "1", 1: "#1", 2: "2", 3: "b3", 4: "3", 5: "4",
        6: "#4", 7: "5", 8: "b6", 9: "6", 10: "b7", 11: "7",
    ]

    /// Formats a chord written in `key` for display.
    ///
    /// - Parameters:
    ///   - transpose: semitones to shift the song (changes the sounding key).
    ///   - capo: capo fret; letter names become the shapes to play with that capo.
    public static func format(
        _ symbol: String, key: MusicalKey?, transpose: Int, capo: Int, notation: ChordNotation
    ) -> String {
        guard let chord = Chord(symbol) else { return symbol }
        switch notation {
        case .letters:
            let shapeKey = key?.transposed(by: transpose - capo)
            return chord.transposed(by: transpose - capo).name(preferFlats: shapeKey?.prefersFlats ?? false)
        case .degrees:
            guard let key else { return symbol }
            // Degrees don't change with transposition or capo.
            let tonic = key.relativeMajorTonic
            var out = degree(chord.root, tonic: tonic) + chord.suffix
            if let bass = chord.bass { out += "/" + degree(bass, tonic: tonic) }
            return out
        }
    }

    private static func degree(_ pitch: PitchClass, tonic: PitchClass) -> String {
        degreeNames[PitchClass(pitch.value - tonic.value).value] ?? "?"
    }
}
