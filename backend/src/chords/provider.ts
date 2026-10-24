import type { ChordAnnotation, Lyrics } from "../types";

export type ProviderName = "anthropic" | "openai";
export const PROVIDER_NAMES: readonly ProviderName[] = ["anthropic", "openai"];

/** An AI model that places chords on numbered lyric lines. */
export interface ChordProvider {
  name: ProviderName;
  model: string;
  annotate(lyrics: Lyrics): Promise<ChordAnnotation>;
}

export type ChordAnnotationErrorCode =
  | "declined" // the model refused
  | "incomplete" // the answer was cut off
  | "invalid_output" // the answer didn't match the schema
  | "rate_limited"
  | "upstream"; // any other API error

/** Provider-neutral failure, so the HTTP layer doesn't need to know each SDK's error types. */
export class ChordAnnotationError extends Error {
  constructor(
    message: string,
    readonly code: ChordAnnotationErrorCode,
    readonly provider: ProviderName,
  ) {
    super(message);
  }
}
