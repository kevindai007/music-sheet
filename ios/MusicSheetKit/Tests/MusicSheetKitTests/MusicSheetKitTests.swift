import Foundation
import Testing
@testable import MusicSheetKit

@Suite struct ChordTests {
    @Test(arguments: [
        ("C", 0, "", nil as Int?),
        ("F#m7", 6, "m7", nil),
        ("Bbmaj7", 10, "maj7", nil),
        ("G/B", 7, "", 11),
        ("Dsus4", 2, "sus4", nil),
        ("Ebm/Gb", 3, "m", 6),
    ])
    func parses(symbol: String, root: Int, suffix: String, bass: Int?) throws {
        let chord = try #require(Chord(symbol))
        #expect(chord.root.value == root)
        #expect(chord.suffix == suffix)
        #expect(chord.bass?.value == bass)
    }

    @Test(arguments: ["", "H", "hello", "C/X", "/G"])
    func rejects(symbol: String) {
        #expect(Chord(symbol) == nil)
    }

    @Test func minorDetection() {
        #expect(Chord("Am7")!.isMinor)
        #expect(!Chord("Cmaj7")!.isMinor)
    }
}

@Suite struct FormatterTests {
    let g = MusicalKey("G")!

    @Test func capoShowsShapes() {
        // Sounding key G with capo 2 is played with F shapes… G - 2 = F, D/F# - 2 = C/E.
        #expect(ChordFormatter.format("G", key: g, transpose: 0, capo: 2, notation: .letters) == "F")
        #expect(ChordFormatter.format("D/F#", key: g, transpose: 0, capo: 2, notation: .letters) == "C/E")
    }

    @Test func transposeUsesKeySpelling() {
        // G up 3 semitones is Bb, a flat key.
        #expect(ChordFormatter.format("D", key: g, transpose: 3, capo: 0, notation: .letters) == "F")
        #expect(ChordFormatter.format("C", key: g, transpose: 3, capo: 0, notation: .letters) == "Eb")
        // G up 1 semitone is Ab: flats too.
        #expect(ChordFormatter.format("G", key: g, transpose: 1, capo: 0, notation: .letters) == "Ab")
        // G up 4 is B: sharps.
        #expect(ChordFormatter.format("Em", key: g, transpose: 4, capo: 0, notation: .letters) == "G#m")
    }

    @Test func degrees() {
        #expect(ChordFormatter.format("G", key: g, transpose: 5, capo: 3, notation: .degrees) == "1")
        #expect(ChordFormatter.format("Em7", key: g, transpose: 0, capo: 0, notation: .degrees) == "6m7")
        #expect(ChordFormatter.format("D/F#", key: g, transpose: 0, capo: 0, notation: .degrees) == "5/7")
        #expect(ChordFormatter.format("F", key: g, transpose: 0, capo: 0, notation: .degrees) == "b7")
        // Minor keys count from the relative major: in Am, Am is 6m and G is 5.
        let am = MusicalKey("Am")!
        #expect(ChordFormatter.format("Am", key: am, transpose: 0, capo: 0, notation: .degrees) == "6m")
        #expect(ChordFormatter.format("G", key: am, transpose: 0, capo: 0, notation: .degrees) == "5")
    }

    @Test func unknownSymbolsPassThrough() {
        #expect(ChordFormatter.format("N.C.", key: g, transpose: 2, capo: 0, notation: .letters) == "N.C.")
    }

    @Test func keyNames() {
        #expect(MusicalKey("G")!.transposed(by: 3).name == "Bb")
        #expect(MusicalKey("Em")!.transposed(by: 1).name == "Fm")
        #expect(MusicalKey("A")!.transposed(by: 1).name == "Bb")
        #expect(MusicalKey("E")!.transposed(by: 2).name == "F#")
    }
}

@Suite struct SegmentTests {
    @Test func splitsAtChords() {
        let line = SongSheet.Line(timeMs: nil, text: "一闪一闪亮晶晶", chords: [
            .init(at: 4, chord: "F"), .init(at: 0, chord: "C"), .init(at: 99, chord: "G"),
        ])
        #expect(line.segments == [
            LineSegment(chord: "C", text: "一闪一闪"),
            LineSegment(chord: "F", text: "亮晶"),
            LineSegment(chord: "G", text: "晶"),
        ])
    }

    @Test func leadingTextWithoutChord() {
        let line = SongSheet.Line(timeMs: nil, text: "啦啦啦", chords: [.init(at: 1, chord: "Am"), .init(at: 1, chord: "G")])
        #expect(line.segments == [
            LineSegment(chord: nil, text: "啦"),
            LineSegment(chord: "Am G", text: "啦啦"),
        ])
    }
}

@Suite struct TimelineTests {
    let sheet = SampleSongs.twinkle

    @Test func syncedUsesTimestamps() {
        let t = PracticeTimeline(sheet: sheet, mode: .synced)
        #expect(t.lineIndex(at: 0) == nil)
        #expect(t.lineIndex(at: 5.3) == 0)
        #expect(t.lineIndex(at: 15.9) == 1)
        #expect(t.lineIndex(at: 999) == 5)
        #expect(t.lines[2] == LineRef(section: 1, line: 0))
    }

    @Test func tempoModeCountsBars() {
        // 90 BPM, 4/4: one bar = 2.666…s; 2 intro bars, 2 bars per line.
        let t = PracticeTimeline(sheet: sheet, mode: .tempo)
        let bar = 60.0 / 90 * 4
        #expect(abs(t.startTime(ofLine: 0) - 2 * bar) < 0.001)
        #expect(abs(t.startTime(ofLine: 1) - 4 * bar) < 0.001)
        #expect(t.lineIndex(at: 4 * bar + 0.01) == 1)
    }

    @Test func syncedFallsBackToTempoWithoutTimestamps() {
        var untimed = sheet
        untimed.sections[0].lines[0].timeMs = nil
        #expect(!PracticeTimeline.canSync(untimed))
        let t = PracticeTimeline(sheet: untimed, mode: .synced, bpm: 60, barsPerLine: 1)
        #expect(t.startTime(ofLine: 1) - t.startTime(ofLine: 0) == 4)
    }
}

@Suite struct APIClientTests {
    @Test func decodesSheet() throws {
        let data = try JSONEncoder().encode(SampleSongs.twinkle)
        let sheet = try APIClient.decodeGenerateResponse(status: 200, data: data)
        #expect(sheet == SampleSongs.twinkle)
    }

    @Test func decodesBackendJSON() throws {
        let json = """
        {"title":"晴天","artist":"周杰伦","album":null,"durationSec":269,"key":"G","capo":0,"bpm":69,
         "timeSignature":"4/4","strumming":"","confidence":"medium","notes":"","introChords":["G"],
         "lyricsSource":{"provider":"lrclib","synced":true},
         "sections":[{"name":"主歌","lines":[{"timeMs":29350,"text":"故事的小黄花","chords":[{"at":0,"chord":"G"}]}]}]}
        """
        let sheet = try APIClient.decodeGenerateResponse(status: 200, data: Data(json.utf8))
        #expect(sheet.sections[0].lines[0].chords == [.init(at: 0, chord: "G")])
        #expect(sheet.album == nil)
    }

    @Test func mapsErrors() {
        #expect(throws: APIClient.APIError.unauthorized) {
            try APIClient.decodeGenerateResponse(status: 401, data: Data())
        }
        let notFound = Data(#"{"error":"lyrics_not_found","message":"没有找到《x》的歌词"}"#.utf8)
        #expect(throws: APIClient.APIError.lyricsNotFound("没有找到《x》的歌词")) {
            try APIClient.decodeGenerateResponse(status: 404, data: notFound)
        }
        #expect(throws: APIClient.APIError.server(status: 502, message: nil)) {
            try APIClient.decodeGenerateResponse(status: 502, data: Data("oops".utf8))
        }
    }
}
