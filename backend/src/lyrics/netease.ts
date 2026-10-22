import type { Lyrics } from "../types";
import { parseLrc } from "./lrc";

// NetEase Cloud Music's public web endpoints. They are undocumented, so this is
// only a fallback for Chinese songs that LRCLIB does not have.
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
  const searchRes = await fetch(`${BASE}/search/get/web?${new URLSearchParams({ s: query, type: "1", limit: "5" })}`, {
    headers: HEADERS,
  });
  if (!searchRes.ok) throw new Error(`NetEase search failed: HTTP ${searchRes.status}`);
  const search = (await searchRes.json()) as { result?: { songs?: NeteaseSong[] } };
  const songs = search.result?.songs ?? [];
  const song = (artist && songs.find((s) => s.artists.some((a) => a.name.includes(artist)))) || songs[0];
  if (!song) return null;

  const lyricRes = await fetch(`${BASE}/song/lyric?${new URLSearchParams({ id: String(song.id), lv: "1" })}`, {
    headers: HEADERS,
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
