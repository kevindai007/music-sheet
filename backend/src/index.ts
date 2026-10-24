import { z } from "zod";
import { AuthError, authenticate, IDENTITY_PROVIDERS, issueSession, verifyIdentityToken, type AuthEnv, type Caller } from "./auth";
import {
  ChordAnnotationError,
  PROVIDER_NAMES,
  ProviderSelectionError,
  selectProvider,
  type AIEnv,
  type ChordProvider,
} from "./chords";
import { annotatePrompt, rearrangePrompt } from "./chords/prompt";
import { fetchLyrics, LyricsUnavailableError } from "./lyrics";
import { buildSheet, sectionStarts, sheetLyrics } from "./sheet";
import { SongSheetInputSchema } from "./types";
import { DEFAULT_DAILY_LIMIT, MemoryUsageStore, today, type UsageStore } from "./usage";

export interface Env extends AIEnv, AuthEnv {
  /** AI calls each signed-in user may make per UTC day. The owner (X-App-Token) is not limited. */
  DAILY_LIMIT?: string;
}

/** Things that live longer than one request. The Node server passes a file-backed store. */
export interface Deps {
  usage: UsageStore;
}

// On Workers this resets whenever the isolate is recycled; good enough until it needs KV.
const defaultDeps: Deps = { usage: new MemoryUsageStore() };

interface Context {
  request: Request;
  env: Env;
  deps: Deps;
  caller: Caller;
}

/** Which AI to use; defaults to the server's configured provider. */
const providerField = z.enum(PROVIDER_NAMES).optional();

const GenerateRequest = z.object({
  title: z.string().trim().min(1).max(200),
  artist: z.string().trim().max(200).optional(),
  provider: providerField,
});

const SignInRequest = z.object({
  provider: z.enum(IDENTITY_PROVIDERS),
  idToken: z.string().min(1).max(8192),
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

function dailyLimit(env: Env): number {
  const limit = Number(env.DAILY_LIMIT);
  return env.DAILY_LIMIT && Number.isInteger(limit) && limit >= 0 ? limit : DEFAULT_DAILY_LIMIT;
}

/** Runs `work` (one AI call) if the caller has quota left today, and counts it only if it succeeds. */
async function metered<T>({ env, deps, caller }: Context, work: () => Promise<T>): Promise<T> {
  if (caller.kind === "owner") return work();
  if (caller.kind === "anonymous") throw new AuthError("请先登录。", "unauthorized");
  const limit = dailyLimit(env);
  const day = today();
  if ((await deps.usage.get(caller.id, day)) >= limit) {
    throw new HttpError(429, { error: "quota_exceeded", message: `今天的 ${limit} 次 AI 生成已经用完了，明天再来吧。` });
  }
  const result = await work();
  await deps.usage.increment(caller.id, day);
  return result;
}

async function signIn({ request, env }: Context) {
  const { provider, idToken } = await parseBody(request, SignInRequest);
  const user = await verifyIdentityToken(provider, idToken, env);
  return { ...(await issueSession(user, env)), user };
}

async function me({ env, deps, caller }: Context) {
  if (caller.kind !== "user") return { user: null, owner: true, usage: { used: 0, limit: null } };
  const used = await deps.usage.get(caller.id, today());
  return { user: { id: caller.id, email: caller.email }, owner: false, usage: { used, limit: dailyLimit(env) } };
}

/** We keep nothing about a user but today's usage count, so deleting the account forgets that. */
async function deleteAccount({ deps, caller }: Context) {
  if (caller.kind === "user") await deps.usage.delete(caller.id);
  return { ok: true };
}

async function generate(ctx: Context) {
  const { request, env } = ctx;
  const { title, artist, provider: requested } = await parseBody(request, GenerateRequest);
  const provider = pickProvider(env, requested);
  const lyrics = await fetchLyrics(title, artist).catch((err) => {
    if (!(err instanceof LyricsUnavailableError)) throw err;
    throw new HttpError(502, { error: "lyrics_unavailable", message: "歌词服务暂时连不上，请稍后再试。", detail: err.failures });
  });
  if (!lyrics) throw new HttpError(404, { error: "lyrics_not_found", message: `没有找到《${title}》的歌词` });

  const annotation = await metered(ctx, () => provider.generate(annotatePrompt(lyrics)));
  return { ...buildSheet(lyrics, annotation), generatedBy: { provider: provider.name, model: provider.model } };
}

async function rearrange(ctx: Context) {
  const { request, env } = ctx;
  const { sheet, style, provider: requested } = await parseBody(request, RearrangeRequest);
  const provider = pickProvider(env, requested);

  const annotation = await metered(ctx, () => provider.generate(rearrangePrompt(sheet, style)));
  // Lyrics and section boundaries stay as they were; only the chords change.
  annotation.sections = sectionStarts(sheet);
  return {
    ...buildSheet(sheetLyrics(sheet), annotation, { style }),
    generatedBy: { provider: provider.name, model: provider.model },
  };
}

interface Route {
  /** Whether the caller must be signed in (or the owner). */
  auth: boolean;
  run: (ctx: Context) => Promise<unknown>;
}

const ROUTES: Record<string, Route> = {
  "POST /auth/signin": { auth: false, run: signIn },
  "GET /auth/me": { auth: true, run: me },
  "DELETE /auth/account": { auth: true, run: deleteAccount },
  "POST /songs/generate": { auth: true, run: generate },
  "POST /songs/rearrange": { auth: true, run: rearrange },
};

const AUTH_STATUS: Record<AuthError["code"], number> = {
  unauthorized: 401,
  invalid_identity: 401,
  provider_unavailable: 400,
};

export async function handle(request: Request, env: Env, deps: Deps = defaultDeps): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") return json({ ok: true });

  const route = ROUTES[`${request.method} ${url.pathname}`];
  if (!route) return json({ error: "not_found" }, 404);

  try {
    const caller: Caller = route.auth ? await authenticate(request, env) : { kind: "anonymous" };
    return json(await route.run({ request, env, deps, caller }));
  } catch (err) {
    if (err instanceof HttpError) return json(err.body, err.status);
    if (err instanceof AuthError) return json({ error: err.code, message: err.message }, AUTH_STATUS[err.code]);
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
export default { fetch: (request: Request, env: Env) => handle(request, env) };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
