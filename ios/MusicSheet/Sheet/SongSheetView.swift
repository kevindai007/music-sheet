import MusicSheetKit
import SwiftUI

/// The practice screen: chords over lyrics, transposition and capo, and auto-scroll.
struct SongSheetView: View {
    @Bindable var song: SavedSong
    /// Saves and opens another song, such as a rearrangement of this one.
    var onOpen: (SavedSong) -> Void = { _ in }

    @AppStorage("chordNotation") private var notation: ChordNotation = .letters
    @AppStorage("barsPerLine") private var barsPerLine = 2
    @State private var mode: PracticeTimeline.Mode = .synced
    @State private var clock = PracticeClock()
    @State private var editing: LineRef?
    @State private var showingRearrange = false

    var body: some View {
        if let sheet = song.sheet {
            content(sheet)
        } else {
            ContentUnavailableView("曲谱数据损坏", systemImage: "exclamationmark.triangle")
        }
    }

    private func content(_ sheet: SongSheet) -> some View {
        let canSync = PracticeTimeline.canSync(sheet)
        let timeline = PracticeTimeline(sheet: sheet, mode: canSync ? mode : .tempo, barsPerLine: barsPerLine)
        let activeIndex = timeline.lineIndex(at: clock.time)
        let key = MusicalKey(sheet.key)
        let format: (String) -> String = { [transpose = song.transpose, capo = song.capo, notation] in
            ChordFormatter.format($0, key: key, transpose: transpose, capo: capo, notation: notation)
        }

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(sheet, key: key, format: format)
                    ForEach(Array(sheet.sections.enumerated()), id: \.offset) { s, section in
                        VStack(alignment: .leading, spacing: 2) {
                            if !section.name.isEmpty {
                                Text(section.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                            }
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { l, line in
                                let ref = LineRef(section: s, line: l)
                                let index = timeline.lines.firstIndex(of: ref) ?? 0
                                LyricLineView(line: line, formatChord: format, isActive: index == activeIndex)
                                    .id(index)
                                    .contentShape(.rect)
                                    .onTapGesture { clock.seek(to: timeline.startTime(ofLine: index)) }
                                    .contextMenu {
                                        Button("编辑和弦", systemImage: "pencil") { editing = ref }
                                        Button("从这句开始", systemImage: "play") {
                                            clock.seek(to: timeline.startTime(ofLine: index))
                                            clock.start()
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .onChange(of: activeIndex) { _, newValue in
                guard clock.isRunning, let newValue else { return }
                // Keep the current line in the upper third so the next lines stay visible.
                withAnimation(.easeInOut) { proxy.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            controls(sheet: sheet, timeline: timeline, activeIndex: activeIndex, canSync: canSync, format: format)
        }
        .navigationTitle(sheet.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { displayMenu(sheet) }
        .sheet(item: $editing) { ref in
            LineEditorView(line: sheet[ref], key: sheet.key) { newLine in
                var updated = sheet
                updated[ref] = newLine
                song.update(updated)
            }
        }
        .sheet(isPresented: $showingRearrange) {
            SignInGate { RearrangeView(sheet: sheet) { onOpen(SavedSong(sheet: $0)) } }
        }
        .onDisappear { clock.pause() }
    }

    private func lyricsSourceLabel(_ source: SongSheet.LyricsSource) -> String {
        let name = switch source.provider {
        case "lrclib": "LRCLIB"
        case "netease": "网易云音乐"
        case "sample": "示例"
        default: source.provider
        }
        return "歌词来源：\(name)\(source.synced ? "（带时间轴）" : "")"
    }

    private func header(_ sheet: SongSheet, key: MusicalKey?, format: (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(sheet.artist).foregroundStyle(.secondary)
                if let style = song.arrangementStyle { ArrangementBadge(style: style) }
            }
            HStack(spacing: 12) {
                let sounding = key?.transposed(by: song.transpose).name ?? sheet.key
                Label("\(sounding) 调", systemImage: "music.note")
                if song.capo > 0 { Label("变调夹 \(song.capo) 品", systemImage: "guitars") }
                Label("\(sheet.bpm) BPM · \(sheet.timeSignature)", systemImage: "metronome")
            }
            .font(.footnote)
            if !sheet.strumming.isEmpty {
                Text("节奏型：\(sheet.strumming)").font(.footnote)
            }
            if !sheet.introChords.isEmpty {
                Text("前奏：" + sheet.introChords.map(format).joined(separator: "  "))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if sheet.confidence != .high {
                Label(
                    sheet.confidence == .low ? "AI 对这首歌的和弦把握不大，建议对照原曲修改。" : "和弦可能和原曲有出入，可以长按某一句修改。",
                    systemImage: "exclamationmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            if !sheet.notes.isEmpty {
                Text(sheet.notes).font(.footnote).foregroundStyle(.secondary)
            }
            Text(lyricsSourceLabel(sheet.lyricsSource))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
    }

    private func controls(
        sheet: SongSheet, timeline: PracticeTimeline, activeIndex: Int?, canSync: Bool, format: @escaping (String) -> String
    ) -> some View {
        let nextIndex = (activeIndex ?? -1) + 1
        let next = timeline.lines.indices.contains(nextIndex) ? sheet[timeline.lines[nextIndex]] : nil

        return VStack(spacing: 8) {
            if let next {
                // What's coming up, so you can get your hand ready.
                HStack(spacing: 6) {
                    Text("下一句").font(.caption).foregroundStyle(.secondary)
                    Text(next.chords.map { format($0.chord) }.joined(separator: " → "))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text(next.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 16) {
                Button { clock.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                Button { clock.toggle() } label: {
                    Image(systemName: clock.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }
                Text(Duration.seconds(clock.time).formatted(.time(pattern: .minuteSecond)))
                    .font(.callout.monospacedDigit())
                Spacer()
                Menu {
                    Picker("速度", selection: $clock.rate) {
                        ForEach([0.5, 0.75, 0.9, 1.0, 1.1, 1.25], id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                    }
                } label: {
                    Text("\(clock.rate, specifier: "%g")×").font(.callout.monospacedDigit())
                }
                if canSync {
                    Picker("滚动方式", selection: $mode) {
                        Text("跟原曲").tag(PracticeTimeline.Mode.synced)
                        Text("按节拍").tag(PracticeTimeline.Mode.tempo)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private func displayMenu(_ sheet: SongSheet) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                clock.pause()
                showingRearrange = true
            } label: {
                Label("AI 改编", systemImage: "wand.and.stars")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("和弦显示", selection: $notation) {
                    Text("和弦名（C、Am）").tag(ChordNotation.letters)
                    Text("级数（1、6m）").tag(ChordNotation.degrees)
                }
                Section("变调（升降 \(song.transpose) 个半音）") {
                    Button("升半音", systemImage: "plus") { song.transpose += 1 }
                    Button("降半音", systemImage: "minus") { song.transpose -= 1 }
                    Button("还原原调", systemImage: "arrow.uturn.backward") { song.transpose = 0 }
                }
                Section("变调夹（第 \(song.capo) 品）") {
                    Button("上移一品", systemImage: "plus") { song.capo = min(song.capo + 1, 11) }
                    Button("下移一品", systemImage: "minus") { song.capo = max(song.capo - 1, 0) }
                }
                Section("按节拍滚动：每句 \(barsPerLine) 小节，\(sheet.bpm) BPM") {
                    Button("每句多一小节", systemImage: "plus") { barsPerLine = min(barsPerLine + 1, 8) }
                    Button("每句少一小节", systemImage: "minus") { barsPerLine = max(barsPerLine - 1, 1) }
                    Button("BPM +5", systemImage: "plus") { setBPM(sheet, sheet.bpm + 5) }
                    Button("BPM -5", systemImage: "minus") { setBPM(sheet, sheet.bpm - 5) }
                }
            } label: {
                Label("显示设置", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func setBPM(_ sheet: SongSheet, _ bpm: Int) {
        var updated = sheet
        updated.bpm = min(max(bpm, 30), 240)
        song.update(updated)
    }
}
