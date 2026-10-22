import type { Lyrics } from "../types";
import { parseLrc, parsePlain } from "./lrc";

const BASE = "https://lrclib.net/api";
const USER_AGENT = "music-sheet (https://github.com/kevindai007/music-sheet)";

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
  const res = await fetch(`${BASE}/search?${params}`, { headers: { "User-Agent": USER_AGENT } });
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
