import { z } from "zod";

/** One lyric line as fetched from a lyrics provider, before chords are added. */
export interface LyricLine {
  /** Start time in milliseconds from the start of the song, when the source is time-synced. */
  timeMs: number | null;
  text: string;
}

export interface Lyrics {
  provider: "lrclib" | "netease";
  title: string;
  artist: string;
  album: string | null;
  durationSec: number | null;
  synced: boolean;
  lines: LyricLine[];
}

/**
 * What Claude returns. It never repeats the lyrics: chords are placed by line
 * number and character offset into lines we already have.
 */
export const ChordAnnotationSchema = z.object({
  key: z.string().describe('Key of the original recording, e.g. "G", "Em", "Bb"'),
  capo: z.number().int().describe("Suggested capo fret for playing in that key with easy shapes; 0 for none"),
  bpm: z.number().int().describe("Approximate tempo of the original recording"),
  timeSignature: z.string().describe('e.g. "4/4", "3/4", "6/8"'),
  strumming: z.string().describe('Suggested strumming pattern, e.g. "D DU UDU"; empty if unsure'),
  confidence: z.enum(["high", "medium", "low"]).describe("How sure you are that the chords match the original recording"),
  notes: z.string().describe("Short practice notes in Chinese; empty if none"),
  introChords: z.array(z.string()).describe("Chords of the instrumental intro, in order"),
  sections: z
    .array(
      z.object({
        name: z.string().describe('Section label, e.g. "主歌 1", "副歌", "桥段"'),
        startLine: z.number().int().describe("Line number where the section starts"),
      }),
    )
    .describe("Song sections in order; the first must start at line 0"),
  chords: z
    .array(
      z.object({
        line: z.number().int().describe("Line number from the input"),
        at: z.number().int().describe("0-based character offset in that line where the chord change lands"),
        chord: z.string().describe('Chord symbol, e.g. "C", "Am7", "G/B", "Dsus4"'),
      }),
    )
    .describe("Every chord change, in song order"),
});

export type ChordAnnotation = z.infer<typeof ChordAnnotationSchema>;

export interface PlacedChord {
  /** 0-based character (Unicode code point) offset into the line text. */
  at: number;
  chord: string;
}

export interface SheetLine {
  timeMs: number | null;
  text: string;
  chords: PlacedChord[];
}

export interface SheetSection {
  name: string;
  lines: SheetLine[];
}

/** The song sheet the iPhone app renders. */
export interface SongSheet {
  title: string;
  artist: string;
  album: string | null;
  durationSec: number | null;
  key: string;
  capo: number;
  bpm: number;
  timeSignature: string;
  strumming: string;
  confidence: "high" | "medium" | "low";
  notes: string;
  introChords: string[];
  lyricsSource: { provider: Lyrics["provider"]; synced: boolean };
  sections: SheetSection[];
}
