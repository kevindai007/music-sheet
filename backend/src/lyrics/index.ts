import type { Lyrics } from "../types";
import { fetchFromLrclib } from "./lrclib";
import { fetchFromNetease } from "./netease";

const PROVIDERS = [fetchFromLrclib, fetchFromNetease];

/** Tries each lyrics provider in turn. A provider that errors is skipped, not fatal. */
export async function fetchLyrics(title: string, artist?: string): Promise<Lyrics | null> {
  for (const provider of PROVIDERS) {
    try {
      const lyrics = await provider(title, artist);
      if (lyrics) return lyrics;
    } catch (err) {
      console.warn(`${provider.name} failed:`, err);
    }
  }
  return null;
}
