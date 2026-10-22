import type { ChordAnnotation, Lyrics, PlacedChord, SheetSection, SongSheet } from "./types";

// Root, optional quality/extensions, optional slash bass: C, F#m7b5, Bbmaj7, Cadd9, G/B, Dsus4, E7(#9).
const CHORD = /^[A-G][#b]?(m|maj|min|dim|aug|sus|add|M)?[0-9]*(sus[24]?|add[0-9]+|maj[0-9]*|[#b+-][0-9]+|\([^)]*\))*(\/[A-G][#b]?)?$/;

export function isChordSymbol(s: string): boolean {
  return CHORD.test(s.trim());
}

/** Merges Claude's chord positions into the fetched lyrics. Bad positions are clamped or dropped. */
export function buildSheet(lyrics: Lyrics, ann: ChordAnnotation): SongSheet {
  const lineCount = lyrics.lines.length;
  const chordsByLine = new Map<number, PlacedChord[]>();
  for (const { line, at, chord } of ann.chords) {
    const lyricLine = lyrics.lines[line];
    if (!lyricLine || !isChordSymbol(chord)) continue;
    const length = Array.from(lyricLine.text).length;
    const placed = { at: Math.min(Math.max(at, 0), Math.max(length - 1, 0)), chord: chord.trim() };
    const list = chordsByLine.get(line) ?? [];
    list.push(placed);
    chordsByLine.set(line, list);
  }

  // Section starts must be in range, ascending, and begin at line 0.
  const starts = [...ann.sections]
    .filter((s) => s.startLine >= 0 && s.startLine < lineCount)
    .sort((a, b) => a.startLine - b.startLine)
    .filter((s, i, arr) => i === 0 || s.startLine !== arr[i - 1]!.startLine);
  if (starts.length === 0 || starts[0]!.startLine !== 0) starts.unshift({ name: "", startLine: 0 });

  const sections: SheetSection[] = starts.map((s, i) => {
    const end = starts[i + 1]?.startLine ?? lineCount;
    return {
      name: s.name,
      lines: lyrics.lines.slice(s.startLine, end).map((l, j) => ({
        timeMs: l.timeMs,
        text: l.text,
        chords: (chordsByLine.get(s.startLine + j) ?? []).sort((a, b) => a.at - b.at),
      })),
    };
  });

  return {
    title: lyrics.title,
    artist: lyrics.artist,
    album: lyrics.album,
    durationSec: lyrics.durationSec,
    key: ann.key,
    capo: Math.max(0, ann.capo),
    bpm: ann.bpm,
    timeSignature: ann.timeSignature,
    strumming: ann.strumming,
    confidence: ann.confidence,
    notes: ann.notes,
    introChords: ann.introChords.filter(isChordSymbol),
    lyricsSource: { provider: lyrics.provider, synced: lyrics.synced },
    sections,
  };
}
