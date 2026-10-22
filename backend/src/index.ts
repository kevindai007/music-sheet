import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { annotateChords, ChordAnnotationError } from "./chords/annotate";
import { fetchLyrics } from "./lyrics";
import { buildSheet } from "./sheet";

export interface Env {
  ANTHROPIC_API_KEY: string;
  APP_TOKEN: string;
}

const GenerateRequest = z.object({
  title: z.string().trim().min(1).max(200),
  artist: z.string().trim().max(200).optional(),
});

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") return json({ ok: true });

    if (request.method === "POST" && url.pathname === "/songs/generate") {
      if (!env.APP_TOKEN || request.headers.get("X-App-Token") !== env.APP_TOKEN) {
        return json({ error: "unauthorized" }, 401);
      }
      const parsed = GenerateRequest.safeParse(await request.json().catch(() => null));
      if (!parsed.success) return json({ error: "invalid_request", detail: parsed.error.issues }, 400);
      const { title, artist } = parsed.data;

      const lyrics = await fetchLyrics(title, artist);
      if (!lyrics) return json({ error: "lyrics_not_found", message: `没有找到《${title}》的歌词` }, 404);

      try {
        const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
        const annotation = await annotateChords(client, lyrics);
        return json(buildSheet(lyrics, annotation));
      } catch (err) {
        if (err instanceof ChordAnnotationError) return json({ error: "chords_failed", message: err.message }, 502);
        if (err instanceof Anthropic.RateLimitError) return json({ error: "rate_limited" }, 429);
        if (err instanceof Anthropic.APIError) return json({ error: "claude_api_error", status: err.status }, 502);
        throw err;
      }
    }

    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
