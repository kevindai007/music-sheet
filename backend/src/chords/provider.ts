import type { ChordAnnotation } from "../types";

export type ProviderName = "anthropic" | "openai";
export const PROVIDER_NAMES: readonly ProviderName[] = ["anthropic", "openai"];

/** A system + user prompt whose answer is a `ChordAnnotation`. */
export interface ChordPrompt {
  system: string;
  user: string;
}

/** An AI model that answers a chord prompt with structured output. Tasks live in the prompt builders, not here. */
export interface ChordProvider {
  name: ProviderName;
  model: string;
  generate(prompt: ChordPrompt): Promise<ChordAnnotation>;
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
