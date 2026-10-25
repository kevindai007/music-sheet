import Foundation
import Testing
@testable import MusicSheetKit

private func frame(_ hex: String) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map {
        UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)...].prefix(2), radix: 16)!
    })
}

@Suite struct LiberLiveTests {
    // Real "noti_chord" frames from a LiberLive C2: a pick played while holding each diatonic button in C (C Dm Em F G Am B°).
    static let presses: [(String, Int, LiberLive.ChordPress.Quality, String)] = [
        ("244124c015249bfe12f3e81e1e791f00e9a954de3d12a161700f6691cca23ab1497b94ae", 0, .major, "C"),
        ("244124c091e8dca96031b63d6e801f00482d98996a60633f537f9f91ce26f4f71e099c7f", 2, .minor, "Dm"),
        ("244124c06c96e81a4d4d2fe537891f0074d0e6add94d1fa68b269691c8db8cc3ad24c68e", 4, .minor, "Em"),
        ("244124c08ed6fa2ae62c49c7608f1f00f532a6bfe9e67ec0a9719091c939cdd09d8f56df", 5, .major, "F"),
        ("244124c0437f968df4958282f7961f0094ff0fd34ef4c70bece68991cbf466bc3a9d0719", 7, .major, "G"),
        ("244124c0b188ef302f0316fe339d1f000c0df8aaf32f519f90228291c5069fc48746814a", 9, .minor, "Am"),
        ("244124c0f98ab9c981a66ae56da31f00b545fafc0a81f4e38b7cbc91c74e9f907ee81c41", 11, .diminished, "Bdim"),
    ]

    @Test(arguments: presses)
    func decodesChordPresses(hex: String, root: Int, quality: LiberLive.ChordPress.Quality, name: String) throws {
        let f = try #require(LiberLive.Frame(frame(hex)))
        #expect(f.direction == .fromGuitar)
        #expect(f.name == "noti_chord")
        let press = try #require(LiberLive.ChordPress(f))
        #expect(press.root.value == root)
        #expect(press.quality == quality)
        #expect(press.pick == 0)
        #expect(press.chord.name(preferFlats: false) == name)
    }

    @Test func decodesTheOfficialAppsCommandAndReply() throws {
        // A get_vers_all request written by the official app and the guitar's reply.
        let request = try #require(LiberLive.Frame(frame("244d20c0ad9f7ed56e64cbcf6ecc93938a17e63116581f44bb63fe1833770395")))
        #expect(request.direction == .toGuitar)
        #expect(request.name == "get_vers_all")
        #expect(request.arguments.isEmpty)

        let reply = try #require(LiberLive.Frame(frame(
            "244167c0941f29dea442e570a70b0000c42e66661d92396a04aa398ba04e080262fd7d2146ec48dafd0c31366fca7e2146f756c4fc"
                + "200a3358e37f3e58e951c4fc12020859fc613f4ef756dbe212310762fd7c2146e948dafc0c313461ca7e2143f756c4fc587e"
        )))
        #expect(reply.timestamp == 2983) // ms since the guitar powered on
        #expect(reply.name == "get_vers_all")
        #expect(String(decoding: reply.arguments, as: UTF8.self).contains("02.05.01.05"))
    }

    @Test func roundTripsFramesByteForByte() throws {
        for (hex, _, _, _) in Self.presses {
            let data = frame(hex)
            #expect(try #require(LiberLive.Frame(data)).data == data)
        }
        let built = LiberLive.Frame(direction: .toGuitar, nonce: [1, 2, 3, 4, 5, 6, 7, 8], timestamp: 42, body: [12] + Array("get_vers_all".utf8))
        #expect(LiberLive.Frame(built.data) == built)
    }

    @Test func rejectsDamagedFrames() {
        var data = frame(Self.presses[0].0)
        data[20] ^= 0x01 // body byte: CRC-16 fails
        #expect(LiberLive.Frame(data) == nil)
        var header = frame(Self.presses[0].0)
        header[5] ^= 0x01 // nonce byte: CRC-8 fails
        #expect(LiberLive.Frame(header) == nil)
        #expect(LiberLive.Frame(Data([0x24, 0x41, 0x03])) == nil)
    }
}

@Suite struct ChordFollowerTests {
    let twinkle = SampleSongs.twinkle

    @Test func collapsesRepeatsAcrossLineBreaks() {
        let follower = ChordFollower(sheet: twinkle)
        // Line 1 ends on C and line 2 starts on C: one press, one step.
        let names = follower.steps.prefix(9).map { "\($0.line):\($0.chord.name(preferFlats: false))" }
        #expect(names == ["0:C", "0:F", "0:C", "1:F", "1:C", "1:G", "1:C", "2:F", "2:C"])
    }

    @Test func advancesOnMatchingPresses() {
        var follower = ChordFollower(sheet: twinkle)
        #expect(follower.currentLine == nil)
        for name in ["C", "F", "C", "F"] {
            let moved = follower.press(Chord(name)!)
            #expect(moved)
        }
        #expect(follower.currentLine == 1)
        #expect(follower.next?.chord == Chord("C"))
    }

    @Test func ignoresWrongChordsAndRepeatedStrums() {
        var follower = ChordFollower(sheet: twinkle)
        let wrong = follower.press(Chord("Am")!)
        #expect(!wrong && follower.position == 0)
        // C F C: strumming C again must not skip the F to reach the second C.
        follower.press(Chord("C")!)
        let again = follower.press(Chord("C")!)
        #expect(!again && follower.position == 1)
    }

    @Test func recoversFromAMissedChange() {
        var follower = ChordFollower(sheet: twinkle)
        for name in ["C", "F", "C"] { follower.press(Chord(name)!) }
        // Next come F, C, G: the player misses F and C and plays G.
        let moved = follower.press(Chord("G")!)
        #expect(moved && follower.position == 6)
        #expect(follower.currentLine == 1)
    }

    @Test func comparesTriadsInTheSoundingKey() {
        let sheet = SongSheet(
            title: "t", artist: "a", key: "G", bpm: 90, lyricsSource: .init(provider: "x", synced: false),
            sections: [.init(name: "", lines: [.init(timeMs: nil, text: "abc", chords: [.init(at: 0, chord: "Em7"), .init(at: 1, chord: "D/F#")])])]
        )
        var follower = ChordFollower(sheet: sheet, transpose: 2)
        // Em7 up two semitones is F#m7; the guitar's F#m button matches it, and D/F# becomes E.
        let minor = follower.press(Chord("F#m")!)
        let wrongBass = follower.press(Chord("D")!)
        #expect(minor && !wrongBass)
        let slash = follower.press(Chord("E")!)
        #expect(slash)
    }

    @Test func jumpsToATappedLine() {
        var follower = ChordFollower(sheet: twinkle)
        follower.jump(toLine: 3)
        #expect(follower.next?.line == 3)
        let moved = follower.press(Chord("C")!)
        #expect(moved && follower.currentLine == 3)
    }
}
