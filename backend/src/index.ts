import { z } from "zod";
import {
  ChordAnnotationError,
  PROVIDER_NAMES,
  ProviderSelectionError,
  selectProvider,
  type AIEnv,
  type ChordProvider,
} from "./chords";
import { annotatePrompt, rearrangePrompt } from "./chords/prompt";
import { fetchLyrics } from "./lyrics";
import { buildSheet, sectionStarts, sheetLyrics } from "./sheet";
import { SongSheetInputSchema } from "./types";

export interface Env extends AIEnv {
  APP_TOKEN: string;
}

/** Which AI to use; defaults to the server's configured provider. */
const providerField = z.enum(PROVIDER_NAMES).optional();

const GenerateRequest = z.object({
  title: z.string().trim().min(1).max(200),
  artist: z.string().trim().max(200).optional(),
  provider: providerField,
});

const RearrangeRequest = z.object({
  sheet: SongSheetInputSchema,
  style: z.string().trim().min(1).max(200),
  provider: providerField,
});

const ERROR_STATUS: Record<ChordAnnotationError["code"], number> = {
  declined: 502,
  incomplete: 502,
  invalid_output: 502,
  rate_limited: 429,
  upstream: 502,
};

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly body: Record<string, unknown>,
  ) {
    super(String(body.error));
  }
}

async function parseBody<T extends z.ZodType>(request: Request, schema: T): Promise<z.infer<T>> {
  const parsed = schema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) throw new HttpError(400, { error: "invalid_request", detail: parsed.error.issues });
  return parsed.data;
}

function pickProvider(env: Env, requested: z.infer<typeof providerField>): ChordProvider {
  try {
    return selectProvider(env, requested);
  } catch (err) {
    if (err instanceof ProviderSelectionError) {
      throw new HttpError(requested ? 400 : 500, { error: "provider_unavailable", message: err.message });
    }
    throw err;
  }
}

async function generate(request: Request, env: Env) {
  const { title, artist, provider: requested } = await parseBody(request, GenerateRequest);
  const provider = pickProvider(env, requested);
  const lyrics = await fetchLyrics(title, artist);
  if (!lyrics) throw new HttpError(404, { error: "lyrics_not_found", message: `没有找到《${title}》的歌词` });

  const annotation = await provider.generate(annotatePrompt(lyrics));
  return { ...buildSheet(lyrics, annotation), generatedBy: { provider: provider.name, model: provider.model } };
}

async function rearrange(request: Request, env: Env) {
  const { sheet, style, provider: requested } = await parseBody(request, RearrangeRequest);
  const provider = pickProvider(env, requested);

  const annotation = await provider.generate(rearrangePrompt(sheet, style));
  // Lyrics and section boundaries stay as they were; only the chords change.
  annotation.sections = sectionStarts(sheet);
  return {
    ...buildSheet(sheetLyrics(sheet), annotation, { style }),
    generatedBy: { provider: provider.name, model: provider.model },
  };
}

const ROUTES: Record<string, (request: Request, env: Env) => Promise<unknown>> = {
  "/songs/generate": generate,
  "/songs/rearrange": rearrange,
};

export async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") return json({ ok: true });

  const route = ROUTES[url.pathname];
  if (request.method !== "POST" || !route) return json({ error: "not_found" }, 404);

  if (!env.APP_TOKEN || request.headers.get("X-App-Token") !== env.APP_TOKEN) {
    return json({ error: "unauthorized" }, 401);
  }
  try {
    return json(await route(request, env));
  } catch (err) {
    if (err instanceof HttpError) return json(err.body, err.status);
    if (err instanceof ChordAnnotationError) {
      return json(
        { error: "chords_failed", code: err.code, provider: err.provider, message: err.message },
        ERROR_STATUS[err.code],
      );
    }
    throw err;
  }
}

/** Cloudflare Workers entry point. The Docker image uses `server.ts` instead. */
export default { fetch: handle };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
