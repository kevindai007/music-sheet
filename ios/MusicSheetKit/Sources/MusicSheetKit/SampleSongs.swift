import Foundation

public enum SampleSongs {
    /// 《小星星》, a public-domain children's song, for trying the app without the backend.
    public static let twinkle = SongSheet(
        title: "小星星",
        artist: "儿歌",
        durationSec: 40,
        key: "C",
        bpm: 90,
        strumming: "D D D D",
        confidence: .high,
        notes: "示例曲谱，不需要连接后端。",
        introChords: ["C", "G"],
        lyricsSource: .init(provider: "sample", synced: true),
        sections: [
            .init(name: "第一段", lines: [
                .init(timeMs: 5_300, text: "一闪一闪亮晶晶", chords: [.init(at: 0, chord: "C"), .init(at: 4, chord: "F"), .init(at: 6, chord: "C")]),
                .init(timeMs: 10_600, text: "满天都是小星星", chords: [.init(at: 0, chord: "F"), .init(at: 2, chord: "C"), .init(at: 4, chord: "G"), .init(at: 6, chord: "C")]),
            ]),
            .init(name: "第二段", lines: [
                .init(timeMs: 16_000, text: "挂在天上放光明", chords: [.init(at: 0, chord: "C"), .init(at: 2, chord: "F"), .init(at: 4, chord: "C"), .init(at: 6, chord: "G")]),
                .init(timeMs: 21_300, text: "好像许多小眼睛", chords: [.init(at: 0, chord: "C"), .init(at: 2, chord: "F"), .init(at: 4, chord: "C"), .init(at: 6, chord: "G")]),
            ]),
            .init(name: "第三段", lines: [
                .init(timeMs: 26_600, text: "一闪一闪亮晶晶", chords: [.init(at: 0, chord: "C"), .init(at: 4, chord: "F"), .init(at: 6, chord: "C")]),
                .init(timeMs: 32_000, text: "满天都是小星星", chords: [.init(at: 0, chord: "F"), .init(at: 2, chord: "C"), .init(at: 4, chord: "G"), .init(at: 6, chord: "C")]),
            ]),
        ]
    )
}
