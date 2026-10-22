import Foundation

/// A run of lyric text with the chord (if any) that starts on its first character.
public struct LineSegment: Hashable, Sendable {
    public var chord: String?
    public var text: String
}

extension SongSheet.Line {
    /// Splits the line at each chord position so a view can draw chords above the right characters.
    /// Out-of-range positions are clamped; chords at the same position are joined with a space.
    public var segments: [LineSegment] {
        let chars = Array(text)
        guard !chars.isEmpty else {
            return chords.isEmpty ? [] : [LineSegment(chord: chords.map(\.chord).joined(separator: " "), text: "")]
        }
        var chordsAt: [Int: [String]] = [:]
        for c in chords {
            chordsAt[min(max(c.at, 0), chars.count - 1), default: []].append(c.chord)
        }
        let cuts = ([0] + chordsAt.keys.sorted()).reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } }
        return cuts.enumerated().map { i, start in
            let end = i + 1 < cuts.count ? cuts[i + 1] : chars.count
            return LineSegment(chord: chordsAt[start]?.joined(separator: " "), text: String(chars[start..<end]))
        }
    }
}
