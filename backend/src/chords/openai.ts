import OpenAI from "openai";
import { zodTextFormat } from "openai/helpers/zod";
import { ChordAnnotationSchema, type Lyrics } from "../types";
import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt";
import { ChordAnnotationError, type ChordProvider } from "./provider";

export const DEFAULT_OPENAI_MODEL = "gpt-5.5";

export function createOpenAIProvider(apiKey: string, model = DEFAULT_OPENAI_MODEL): ChordProvider {
  const client = new OpenAI({ apiKey });
  const fail = (message: string, code: ChordAnnotationError["code"]) =>
    new ChordAnnotationError(message, code, "openai");

  return {
    name: "openai",
    model,
    async annotate(lyrics: Lyrics) {
      let response;
      try {
        response = await client.responses.parse({
          model,
          instructions: SYSTEM_PROMPT,
          input: buildUserPrompt(lyrics),
          text: { format: zodTextFormat(ChordAnnotationSchema, "chord_annotation") },
        });
      } catch (err) {
        if (err instanceof OpenAI.RateLimitError) throw fail("OpenAI rate limit reached", "rate_limited");
        if (err instanceof OpenAI.APIError) throw fail(`OpenAI API error (HTTP ${err.status})`, "upstream");
        throw err;
      }

      const refused = response.output.some(
        (item) => item.type === "message" && item.content.some((c) => c.type === "refusal"),
      );
      if (refused) throw fail("OpenAI declined the request", "declined");
      if (response.status === "incomplete") {
        throw fail(`OpenAI's answer was cut off (${response.incomplete_details?.reason ?? "unknown"})`, "incomplete");
      }
      if (!response.output_parsed) {
        throw fail("OpenAI's answer did not match the chord schema", "invalid_output");
      }
      return response.output_parsed;
    },
  };
}
