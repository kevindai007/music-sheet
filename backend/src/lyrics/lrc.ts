import type { LyricLine } from "../types";

const TIME_TAG = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

// Credit lines that providers mix into the lyrics, e.g. "作词 : 周杰伦".
const CREDIT_LINE = /^(作词|作曲|编曲|制作人|监制|和声|混音|母带|吉他|贝斯|鼓|录音|出品|词|曲|lyrics|composer|arranger|producer)\s*[:：]/i;

/** Parses LRC text into time-ordered lines. Lines can carry several time tags. */
export function parseLrc(lrc: string): LyricLine[] {
  const lines: LyricLine[] = [];
  for (const raw of lrc.split(/\r?\n/)) {
    const times: number[] = [];
    for (const m of raw.matchAll(TIME_TAG)) {
      const [, min, sec, frac = "0"] = m;
      const ms = frac.length === 1 ? Number(frac) * 100 : frac.length === 2 ? Number(frac) * 10 : Number(frac);
      times.push(Number(min) * 60_000 + Number(sec) * 1000 + ms);
    }
    if (times.length === 0) continue; // metadata tags like [ar:...] or untimed text
    const text = raw.replace(TIME_TAG, "").trim();
    if (!isLyric(text)) continue;
    for (const timeMs of times) lines.push({ timeMs, text });
  }
  return lines.sort((a, b) => (a.timeMs ?? 0) - (b.timeMs ?? 0));
}

/** Splits plain (untimed) lyrics into lines. */
export function parsePlain(text: string): LyricLine[] {
  return text
    .split(/\r?\n/)
    .map((t) => t.trim())
    .filter(isLyric)
    .map((t) => ({ timeMs: null, text: t }));
}

function isLyric(text: string): boolean {
  return text.length > 0 && !CREDIT_LINE.test(text);
}
