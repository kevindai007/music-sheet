import Foundation

/// Maps elapsed practice time to the line being sung, for auto-scroll.
public struct PracticeTimeline: Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        /// Follow the lyrics' timestamps from the original recording.
        case synced
        /// Estimate line times from the tempo: a fixed number of bars per line.
        case tempo
    }

    public let lines: [LineRef]
    /// Start time of each line in seconds of song time, ascending.
    public let startTimes: [Double]

    public init(sheet: SongSheet, mode: Mode, bpm: Int? = nil, barsPerLine: Int = 2) {
        lines = sheet.allLines
        let timed = lines.map { sheet[$0].timeMs }
        if mode == .synced, !timed.isEmpty, timed.allSatisfy({ $0 != nil }) {
            startTimes = timed.map { Double($0!) / 1000 }
        } else {
            let beat = 60 / Double(max(bpm ?? sheet.bpm, 1))
            let bar = beat * Double(sheet.beatsPerBar)
            let intro = bar * Double(sheet.introChords.count)
            startTimes = lines.indices.map { intro + Double($0 * max(barsPerLine, 1)) * bar }
        }
    }

    /// Whether every line has a timestamp, so `.synced` mode is usable.
    public static func canSync(_ sheet: SongSheet) -> Bool {
        let lines = sheet.allLines
        return !lines.isEmpty && lines.allSatisfy { sheet[$0].timeMs != nil }
    }

    /// Index into `lines` of the line playing at `time` seconds, or nil before the first line.
    public func lineIndex(at time: Double) -> Int? {
        // Last start time <= time (binary search).
        var lo = 0, hi = startTimes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if startTimes[mid] <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }

    /// Song time at which the line at `index` starts; used to jump when the user taps a line.
    public func startTime(ofLine index: Int) -> Double {
        startTimes.indices.contains(index) ? startTimes[index] : 0
    }
}
