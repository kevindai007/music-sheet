import type { Lyrics } from "../types";
import { parseLrc } from "./lrc";

// NetEase Cloud Music's public web endpoints. They are undocumented, so this is
// only a fallback for Chinese songs that LRCLIB does not have.
// A slow provider should fall through to the next one, not eat the whole request.
const TIMEOUT_MS = 15_000;
const BASE = "https://music.163.com/api";
const HEADERS = { Referer: "https://music.163.com/", "User-Agent": "Mozilla/5.0" };

interface NeteaseSong {
  id: number;
  name: string;
  artists: { name: string }[];
  album: { name: string } | null;
  duration: number;
}

export async function fetchFromNetease(title: string, artist?: string): Promise<Lyrics | null> {
  const query = artist ? `${title} ${artist}` : title;
  // The GET variant (/search/get/web) now answers with an encrypted string; the POST form still returns JSON.
  const searchRes = await fetch(`${BASE}/search/get`, {
    method: "POST",
    headers: HEADERS,
    body: new URLSearchParams({ s: query, type: "1", limit: "5" }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!searchRes.ok) throw new Error(`NetEase search failed: HTTP ${searchRes.status}`);
  const search = (await searchRes.json()) as { result?: { songs?: NeteaseSong[] } };
  const songs = search.result?.songs ?? [];
  const song = (artist && songs.find((s) => s.artists.some((a) => a.name.includes(artist)))) || songs[0];
  if (!song) return null;

  const lyricRes = await fetch(`${BASE}/song/lyric?${new URLSearchParams({ id: String(song.id), lv: "1" })}`, {
    headers: HEADERS,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!lyricRes.ok) throw new Error(`NetEase lyric fetch failed: HTTP ${lyricRes.status}`);
  const lyric = (await lyricRes.json()) as { lrc?: { lyric?: string } };
  const lines = parseLrc(lyric.lrc?.lyric ?? "");
  if (lines.length === 0) return null;

  return {
    provider: "netease",
    title: song.name,
    artist: song.artists.map((a) => a.name).join(" / "),
    album: song.album?.name ?? null,
    durationSec: Math.round(song.duration / 1000),
    synced: true,
    lines,
  };
}
