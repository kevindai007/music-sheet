import { describe, expect, it } from "vitest";
import { buildSheet, isChordSymbol } from "../src/sheet";
import type { ChordAnnotation, Lyrics } from "../src/types";

const lyrics: Lyrics = {
  provider: "lrclib",
  title: "晴天",
  artist: "周杰伦",
  album: "叶惠美",
  durationSec: 269,
  synced: true,
  lines: [
    { timeMs: 1000, text: "故事的小黄花" },
    { timeMs: 2000, text: "从出生那年就飘着" },
    { timeMs: 3000, text: "刮风这天" },
  ],
};

const annotation: ChordAnnotation = {
  key: "G",
  capo: 0,
  bpm: 69,
  timeSignature: "4/4",
  strumming: "D DU UDU",
  confidence: "medium",
  notes: "",
  introChords: ["G", "D/F#", "not-a-chord"],
  sections: [
    { name: "副歌", startLine: 2 },
    { name: "主歌", startLine: 0 },
    { name: "越界", startLine: 99 },
  ],
  chords: [
    { line: 0, at: 3, chord: "D/F#" },
    { line: 0, at: 0, chord: "G" },
    { line: 1, at: 50, chord: "Em7" },
    { line: 7, at: 0, chord: "C" },
    { line: 2, at: 0, chord: "hello" },
  ],
};

describe("isChordSymbol", () => {
  it.each(["C", "Am", "F#m7b5", "Bbmaj7", "Cadd9", "G/B", "Dsus4", "E7(#9)", "Cmaj7/E"])("accepts %s", (c) =>
    expect(isChordSymbol(c)).toBe(true),
  );
  it.each(["", "H", "hello", "C/X", "Am 7"])("rejects %s", (c) => expect(isChordSymbol(c)).toBe(false));
});

describe("buildSheet", () => {
  const sheet = buildSheet(lyrics, annotation);

  it("groups lines into ordered sections and drops out-of-range ones", () => {
    expect(sheet.sections.map((s) => [s.name, s.lines.map((l) => l.text)])).toEqual([
      ["主歌", ["故事的小黄花", "从出生那年就飘着"]],
      ["副歌", ["刮风这天"]],
    ]);
  });

  it("sorts chords within a line, clamps offsets, and drops invalid chords", () => {
    const [first, second] = sheet.sections[0]!.lines;
    expect(first!.chords).toEqual([
      { at: 0, chord: "G" },
      { at: 3, chord: "D/F#" },
    ]);
    expect(second!.chords).toEqual([{ at: 7, chord: "Em7" }]);
    expect(sheet.sections[1]!.lines[0]!.chords).toEqual([]);
    expect(sheet.introChords).toEqual(["G", "D/F#"]);
  });

  it("adds an unnamed first section when Claude's sections do not start at line 0", () => {
    const s = buildSheet(lyrics, { ...annotation, sections: [{ name: "副歌", startLine: 2 }] });
    expect(s.sections.map((x) => x.name)).toEqual(["", "副歌"]);
  });
});
