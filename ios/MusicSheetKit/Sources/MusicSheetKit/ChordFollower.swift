import Foundation

/// Follows a song by the chord buttons pressed on a LiberLive guitar: each press that matches the next chord change
/// moves the position forward, so the sheet scrolls with the player instead of a clock.
public struct ChordFollower: Sendable {
    public struct Step: Equatable, Sendable {
        /// Index into `SongSheet.allLines`.
        public var line: Int
        public var chord: Chord
    }

    /// The song's chord changes in order. A chord that repeats across a line break is one step, because the
    /// player keeps holding the same button.
    public let steps: [Step]
    /// Index into `steps` of the chord the player should press next.
    public private(set) var position = 0

    /// How many steps ahead a press may match, so one missed or extra change doesn't lose the place.
    static let lookahead = 2

    /// - Parameter transpose: semitones the song is shifted, so the buttons are compared with the sounding chords.
    public init(sheet: SongSheet, transpose: Int = 0) {
        var steps: [Step] = []
        for (index, ref) in sheet.allLines.enumerated() {
            for placed in sheet[ref].chords {
                guard let chord = Chord(placed.chord)?.transposed(by: transpose) else { continue }
                if let last = steps.last, Self.sameButton(last.chord, chord) { continue }
                steps.append(Step(line: index, chord: chord))
            }
        }
        self.steps = steps
    }

    /// The chord the player should press next, or nil at the end of the song.
    public var next: Step? {
        steps.indices.contains(position) ? steps[position] : nil
    }

    /// Line of the chord last matched, or nil before the first match.
    public var currentLine: Int? {
        position > 0 ? steps[position - 1].line : nil
    }

    /// Handles a button press. Returns true when it matched and the position moved.
    @discardableResult
    public mutating func press(_ chord: Chord) -> Bool {
        let end = min(position + Self.lookahead + 1, steps.count)
        guard let hit = (position..<end).first(where: { Self.sameButton(steps[$0].chord, chord) }) else { return false }
        position = hit + 1
        return true
    }

    /// Restarts from the first chord of `line` (an index into `SongSheet.allLines`), e.g. after the user taps a line.
    public mutating func jump(toLine line: Int) {
        position = steps.firstIndex { $0.line >= line } ?? steps.count
    }

    /// LiberLive buttons play triads, so compare root and triad quality and ignore extensions and slash basses.
    static func sameButton(_ a: Chord, _ b: Chord) -> Bool {
        a.root == b.root && triad(a) == triad(b)
    }

    private static func triad(_ chord: Chord) -> Int {
        if chord.suffix.hasPrefix("dim") || chord.suffix.hasPrefix("°") || chord.suffix.hasPrefix("m7b5") { return 2 }
        return chord.isMinor ? 1 : 0
    }
}
