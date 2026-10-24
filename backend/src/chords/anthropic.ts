import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { ChordAnnotationSchema, type Lyrics } from "../types";
import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt";
import { ChordAnnotationError, type ChordProvider } from "./provider";

export const DEFAULT_ANTHROPIC_MODEL = "claude-opus-5-5";

export function createAnthropicProvider(apiKey: string, model = DEFAULT_ANTHROPIC_MODEL): ChordProvider {
  const client = new Anthropic({ apiKey });
  const fail = (message: string, code: ChordAnnotationError["code"]) =>
    new ChordAnnotationError(message, code, "anthropic");

  return {
    name: "anthropic",
    model,
    async annotate(lyrics: Lyrics) {
      let response;
      try {
        response = await client.beta.messages.parse({
          model,
          max_tokens: 16000,
          system: SYSTEM_PROMPT,
          messages: [{ role: "user", content: buildUserPrompt(lyrics) }],
          output_config: { effort: "high", format: betaZodOutputFormat(ChordAnnotationSchema) },
          // Re-run a safety-classifier decline on Anthropic's recommended fallback model.
          fallbacks: "default",
          betas: ["server-side-fallback-2026-07-01"],
        });
      } catch (err) {
        if (err instanceof Anthropic.RateLimitError) throw fail("Claude rate limit reached", "rate_limited");
        if (err instanceof Anthropic.APIError) throw fail(`Claude API error (HTTP ${err.status})`, "upstream");
        throw err;
      }

      if (response.stop_reason === "refusal") {
        throw fail(`Claude declined the request (${response.stop_details?.category ?? "unknown"})`, "declined");
      }
      if (response.stop_reason === "max_tokens") {
        throw fail("Claude's answer was cut off before it finished", "incomplete");
      }
      if (!response.parsed_output) {
        throw fail("Claude's answer did not match the chord schema", "invalid_output");
      }
      return response.parsed_output;
    },
  };
}
