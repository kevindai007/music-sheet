import { z } from "zod";
import { ChordAnnotationError, PROVIDER_NAMES, ProviderSelectionError, selectProvider, type AIEnv } from "./chords";
import { fetchLyrics } from "./lyrics";
import { buildSheet } from "./sheet";

export interface Env extends AIEnv {
  APP_TOKEN: string;
}

const GenerateRequest = z.object({
  title: z.string().trim().min(1).max(200),
  artist: z.string().trim().max(200).optional(),
  /** Which AI to use; defaults to the server's configured provider. */
  provider: z.enum(PROVIDER_NAMES).optional(),
});

const ERROR_STATUS: Record<ChordAnnotationError["code"], number> = {
  declined: 502,
  incomplete: 502,
  invalid_output: 502,
  rate_limited: 429,
  upstream: 502,
};

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
      const { title, artist, provider: requested } = parsed.data;

      let provider;
      try {
        provider = selectProvider(env, requested);
      } catch (err) {
        if (err instanceof ProviderSelectionError) {
          return json({ error: "provider_unavailable", message: err.message }, requested ? 400 : 500);
        }
        throw err;
      }

      const lyrics = await fetchLyrics(title, artist);
      if (!lyrics) return json({ error: "lyrics_not_found", message: `没有找到《${title}》的歌词` }, 404);

      try {
        const annotation = await provider.annotate(lyrics);
        return json({ ...buildSheet(lyrics, annotation), generatedBy: { provider: provider.name, model: provider.model } });
      } catch (err) {
        if (err instanceof ChordAnnotationError) {
          return json({ error: "chords_failed", code: err.code, provider: err.provider, message: err.message }, ERROR_STATUS[err.code]);
        }
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
