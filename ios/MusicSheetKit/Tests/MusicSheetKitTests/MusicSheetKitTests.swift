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
        let sheet = try APIClient.decodeSheetResponse(status: 200, data: data)
        #expect(sheet == SampleSongs.twinkle)
    }

    @Test func decodesBackendJSON() throws {
        let json = """
        {"title":"晴天","artist":"周杰伦","album":null,"durationSec":269,"key":"G","capo":0,"bpm":69,
         "timeSignature":"4/4","strumming":"","confidence":"medium","notes":"","introChords":["G"],
         "lyricsSource":{"provider":"lrclib","synced":true},
         "sections":[{"name":"主歌","lines":[{"timeMs":29350,"text":"故事的小黄花","chords":[{"at":0,"chord":"G"}]}]}]}
        """
        let sheet = try APIClient.decodeSheetResponse(status: 200, data: Data(json.utf8))
        #expect(sheet.sections[0].lines[0].chords == [.init(at: 0, chord: "G")])
        #expect(sheet.album == nil)
        #expect(sheet.arrangement == nil)
    }

    @Test func decodesArrangementAndProvider() throws {
        var original = SampleSongs.twinkle
        original.arrangement = .init(style: "爵士")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["generatedBy"] = ["provider": "openai", "model": "gpt-5.5"]
        let sheet = try APIClient.decodeSheetResponse(status: 200, data: JSONSerialization.data(withJSONObject: json))
        #expect(sheet.arrangement?.style == "爵士")
        #expect(sheet.generatedBy?.provider == "openai")
    }

    @Test func encodesSheetForRearrange() throws {
        // The backend validates these fields, so the app must send them all.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SampleSongs.twinkle)) as! [String: Any]
        for key in ["title", "artist", "key", "capo", "bpm", "timeSignature", "strumming", "confidence", "notes",
                    "introChords", "lyricsSource", "sections"] {
            #expect(json[key] != nil, "missing \(key)")
        }
    }

    @Test func mapsErrors() {
        #expect(throws: APIClient.APIError.unauthorized) {
            try APIClient.decodeSheetResponse(status: 401, data: Data())
        }
        let notFound = Data(#"{"error":"lyrics_not_found","message":"没有找到《x》的歌词"}"#.utf8)
        #expect(throws: APIClient.APIError.lyricsNotFound("没有找到《x》的歌词")) {
            try APIClient.decodeSheetResponse(status: 404, data: notFound)
        }
        #expect(throws: APIClient.APIError.server(status: 502, message: nil)) {
            try APIClient.decodeSheetResponse(status: 502, data: Data("oops".utf8))
        }
        let quota = Data(#"{"error":"quota_exceeded","message":"今天的 20 次 AI 生成已经用完了"}"#.utf8)
        #expect(throws: APIClient.APIError.quotaExceeded("今天的 20 次 AI 生成已经用完了")) {
            try APIClient.decodeSheetResponse(status: 429, data: quota)
        }
        // An AI rate limit is also a 429, but not the user's quota.
        let rateLimited = Data(#"{"error":"chords_failed","code":"rate_limited","message":"slow down"}"#.utf8)
        #expect(throws: APIClient.APIError.server(status: 429, message: "slow down")) {
            try APIClient.decodeSheetResponse(status: 429, data: rateLimited)
        }
    }

    @Test func decodesAuthResponses() throws {
        let signIn = Data(#"{"sessionToken":"s","expiresAt":"2026-11-23T00:00:00.000Z","user":{"id":"apple:1","email":null}}"#.utf8)
        let result: APIClient.SignInResult = try APIClient.decodeResponse(status: 200, data: signIn)
        #expect(result.user == .init(id: "apple:1", email: nil))

        let me = Data(#"{"user":null,"owner":true,"usage":{"used":0,"limit":null}}"#.utf8)
        let account: APIClient.Account = try APIClient.decodeResponse(status: 200, data: me)
        #expect(account.owner && account.usage.limit == nil)
    }
}

@Suite struct GoogleOAuthTests {
    let google = GoogleOAuth(clientID: "123-abc.apps.googleusercontent.com")

    @Test func redirectUsesReversedClientID() {
        #expect(google.callbackScheme == "com.googleusercontent.apps.123-abc")
        #expect(google.redirectURI == "com.googleusercontent.apps.123-abc:/oauthredirect")
        let url = google.authorizationURL(state: "st", codeChallenge: "ch")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains(.init(name: "code_challenge_method", value: "S256")))
        #expect(items.contains(.init(name: "redirect_uri", value: google.redirectURI)))
    }

    @Test func pkceChallengeMatchesRFC7636() {
        #expect(GoogleOAuth.codeChallenge(for: "dBjftJeZ4CVP-mJ92K9qkt0Ei4RsS4y3_SrGq-LQ_9s")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let token = GoogleOAuth.randomToken()
        #expect(token.count == 43 && !token.contains("=") && token != GoogleOAuth.randomToken())
    }

    @Test func readsTheCallback() throws {
        let ok = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?state=st&code=4/abc")!
        #expect(try google.code(fromCallback: ok, expectedState: "st") == "4/abc")
        #expect(throws: GoogleOAuth.OAuthError.invalidCallback) {
            try google.code(fromCallback: ok, expectedState: "other")
        }
        let denied = URL(string: "com.googleusercontent.apps.123-abc:/oauthredirect?error=access_denied&state=st")!
        #expect(throws: GoogleOAuth.OAuthError.cancelled) {
            try google.code(fromCallback: denied, expectedState: "st")
        }
    }

    @Test func tokenRequestIsFormEncoded() throws {
        let request = google.tokenRequest(code: "4/a+b", codeVerifier: "v")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=v"))
        #expect(!body.contains("4/a+b")) // "+" must be escaped or Google reads it as a space
    }
}
