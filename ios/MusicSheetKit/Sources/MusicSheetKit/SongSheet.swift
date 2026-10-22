import Foundation

/// A song sheet as returned by the backend's `POST /songs/generate`.
/// Chords are written in the sounding key; capo and transposition are applied at display time.
public struct SongSheet: Codable, Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSec: Int?
    public var key: String
    public var capo: Int
    public var bpm: Int
    public var timeSignature: String
    public var strumming: String
    public var confidence: Confidence
    public var notes: String
    public var introChords: [String]
    public var lyricsSource: LyricsSource
    public var sections: [Section]

    public enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    public struct LyricsSource: Codable, Hashable, Sendable {
        public var provider: String
        public var synced: Bool

        public init(provider: String, synced: Bool) {
            self.provider = provider
            self.synced = synced
        }
    }

    public struct Section: Codable, Hashable, Sendable {
        public var name: String
        public var lines: [Line]

        public init(name: String, lines: [Line]) {
            self.name = name
            self.lines = lines
        }
    }

    public struct Line: Codable, Hashable, Sendable {
        /// Start time in milliseconds when the lyrics are time-synced.
        public var timeMs: Int?
        public var text: String
        public var chords: [PlacedChord]

        public init(timeMs: Int?, text: String, chords: [PlacedChord]) {
            self.timeMs = timeMs
            self.text = text
            self.chords = chords
        }
    }

    public struct PlacedChord: Codable, Hashable, Sendable {
        /// 0-based character offset into the line text.
        public var at: Int
        public var chord: String

        public init(at: Int, chord: String) {
            self.at = at
            self.chord = chord
        }
    }

    public init(
        title: String, artist: String, album: String? = nil, durationSec: Int? = nil,
        key: String, capo: Int = 0, bpm: Int, timeSignature: String = "4/4",
        strumming: String = "", confidence: Confidence = .medium, notes: String = "",
        introChords: [String] = [], lyricsSource: LyricsSource, sections: [Section]
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSec = durationSec
        self.key = key
        self.capo = capo
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.strumming = strumming
        self.confidence = confidence
        self.notes = notes
        self.introChords = introChords
        self.lyricsSource = lyricsSource
        self.sections = sections
    }

    /// Beats per bar from the time signature's numerator; 4 when it can't be read.
    public var beatsPerBar: Int {
        Int(timeSignature.split(separator: "/").first ?? "") ?? 4
    }

    /// Every line in song order, with its position in `sections`.
    public var allLines: [LineRef] {
        sections.enumerated().flatMap { s, section in
            section.lines.indices.map { LineRef(section: s, line: $0) }
        }
    }

    public subscript(ref: LineRef) -> Line {
        get { sections[ref.section].lines[ref.line] }
        set { sections[ref.section].lines[ref.line] = newValue }
    }
}

public struct LineRef: Hashable, Identifiable, Sendable {
    public var section: Int
    public var line: Int

    public init(section: Int, line: Int) {
        self.section = section
        self.line = line
    }

    public var id: Self { self }
}
