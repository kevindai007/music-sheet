import Foundation

/// A pitch class (0 = C … 11 = B).
public struct PitchClass: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    private static let naturals: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Parses a note name such as "C", "F#" or "Bb".
    public init?(name: some StringProtocol) {
        guard let letter = name.first, let base = Self.naturals[letter] else { return nil }
        switch name.dropFirst() {
        case "": self.init(base)
        case "#", "♯": self.init(base + 1)
        case "b", "♭": self.init(base - 1)
        default: return nil
        }
    }

    public func name(preferFlats: Bool) -> String {
        preferFlats ? Self.flatNames[value] : Self.sharpNames[value]
    }

    public func transposed(by semitones: Int) -> PitchClass {
        PitchClass(value + semitones)
    }
}

/// A chord symbol split into root, quality/extensions and optional slash bass, e.g. "F#m7/C#".
public struct Chord: Hashable, Sendable {
    public var root: PitchClass
    public var suffix: String
    public var bass: PitchClass?

    public init(root: PitchClass, suffix: String = "", bass: PitchClass? = nil) {
        self.root = root
        self.suffix = suffix
        self.bass = bass
    }

    public init?(_ symbol: String) {
        let s = symbol.trimmingCharacters(in: .whitespaces)
        guard let first = s.first, "ABCDEFG".contains(first) else { return nil }

        var body = Substring(s)
        var bass: PitchClass?
        if let slash = body.lastIndex(of: "/") {
            guard let b = PitchClass(name: body[body.index(after: slash)...]) else { return nil }
            bass = b
            body = body[..<slash]
        }
        var rootEnd = body.index(after: body.startIndex)
        if rootEnd < body.endIndex, "#b♯♭".contains(body[rootEnd]) {
            rootEnd = body.index(after: rootEnd)
        }
        guard let root = PitchClass(name: body[..<rootEnd]) else { return nil }
        self.init(root: root, suffix: String(body[rootEnd...]), bass: bass)
    }

    /// True for minor chords ("m", "m7", "min"), not for "maj7".
    public var isMinor: Bool {
        (suffix.hasPrefix("m") && !suffix.hasPrefix("maj")) || suffix.hasPrefix("min")
    }

    public func transposed(by semitones: Int) -> Chord {
        Chord(root: root.transposed(by: semitones), suffix: suffix, bass: bass?.transposed(by: semitones))
    }

    public func name(preferFlats: Bool) -> String {
        var out = root.name(preferFlats: preferFlats) + suffix
        if let bass { out += "/" + bass.name(preferFlats: preferFlats) }
        return out
    }
}
