import type { Lyrics } from "../types";
import { parseLrc, parsePlain } from "./lrc";

// A slow provider should fall through to the next one, not eat the whole request.
const TIMEOUT_MS = 15_000;
const BASE = "https://lrclib.net/api";
const USER_AGENT = "music-sheet (https://github.com/kevindai007/music-sheet)";
// LRCLIB often answers 503 "ServerOverloaded" for a moment; wait and ask again before giving up on it.
const RETRY_DELAYS_MS = [500, 1500];

interface LrclibTrack {
  trackName: string;
  artistName: string;
  albumName: string | null;
  duration: number | null;
  instrumental: boolean;
  plainLyrics: string | null;
  syncedLyrics: string | null;
}

/** Searches LRCLIB (https://lrclib.net), preferring results with time-synced lyrics. */
export async function fetchFromLrclib(title: string, artist?: string): Promise<Lyrics | null> {
  const params = new URLSearchParams({ track_name: title });
  if (artist) params.set("artist_name", artist);
  const res = await search(`${BASE}/search?${params}`);
  if (!res.ok) throw new Error(`LRCLIB search failed: HTTP ${res.status}`);
  const tracks = (await res.json()) as LrclibTrack[];

  const withLyrics = tracks.filter((t) => !t.instrumental && (t.syncedLyrics || t.plainLyrics));
  const best = withLyrics.find((t) => t.syncedLyrics) ?? withLyrics[0];
  if (!best) return null;

  const lines = best.syncedLyrics ? parseLrc(best.syncedLyrics) : parsePlain(best.plainLyrics ?? "");
  if (lines.length === 0) return null;
  return {
    provider: "lrclib",
    title: best.trackName,
    artist: best.artistName,
    album: best.albumName,
    durationSec: best.duration,
    synced: Boolean(best.syncedLyrics),
    lines,
  };
}

async function search(url: string): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(TIMEOUT_MS) });
    const delay = RETRY_DELAYS_MS[attempt];
    if ((res.status !== 503 && res.status !== 429) || delay === undefined) return res;
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
}
