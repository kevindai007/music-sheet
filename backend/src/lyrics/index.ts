import type { Lyrics } from "../types";
import { fetchFromLrclib } from "./lrclib";
import { fetchFromNetease } from "./netease";

const PROVIDERS = [fetchFromLrclib, fetchFromNetease];

/** Every provider failed (network, blocked, HTTP error), so "not found" would be a guess. */
export class LyricsUnavailableError extends Error {
  constructor(readonly failures: string[]) {
    super(`all lyrics providers failed: ${failures.join("; ")}`);
  }
}

/**
 * Tries each lyrics provider in turn. A provider that errors is skipped, not fatal.
 * Returns null when at least one provider answered and none had the song.
 */
export async function fetchLyrics(title: string, artist?: string): Promise<Lyrics | null> {
  const failures: string[] = [];
  for (const provider of PROVIDERS) {
    try {
      const lyrics = await provider(title, artist);
      if (lyrics) return lyrics;
    } catch (err) {
      console.warn(`${provider.name} failed:`, err);
      failures.push(`${provider.name}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
  if (failures.length === PROVIDERS.length) throw new LyricsUnavailableError(failures);
  return null;
}
