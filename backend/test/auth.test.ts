import { exportJWK, generateKeyPair, SignJWT, type CryptoKey } from "jose";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { handle, type Deps, type Env } from "../src/index";
import type { ChordAnnotation } from "../src/types";
import { MemoryUsageStore } from "../src/usage";

const env: Env = {
  ANTHROPIC_API_KEY: "sk-ant-test",
  APP_TOKEN: "owner-secret",
  SESSION_SECRET: "session-secret-for-tests",
  GOOGLE_CLIENT_IDS: "123-abc.apps.googleusercontent.com",
  DAILY_LIMIT: "2",
};

const annotation: ChordAnnotation = {
  key: "C",
  capo: 0,
  bpm: 80,
  timeSignature: "4/4",
  strumming: "",
  confidence: "high",
  notes: "",
  introChords: [],
  sections: [{ name: "主歌", startLine: 0 }],
  chords: [{ line: 0, at: 0, chord: "C" }],
};

let keys: { privateKey: CryptoKey; jwk: object };
let deps: Deps;

beforeAll(async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  keys = { privateKey, jwk: { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256", use: "sig" } };
});

beforeEach(() => {
  deps = { usage: new MemoryUsageStore() };
  let aiCalls = 0;
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(new Request(input, init).url);
      if (url.href === "https://appleid.apple.com/auth/keys" || url.href === "https://www.googleapis.com/oauth2/v3/certs") {
        return Response.json({ keys: [keys.jwk] });
      }
      if (url.host === "lrclib.net") {
        return Response.json([
          { trackName: "歌", artistName: "人", albumName: null, duration: 1, instrumental: false, plainLyrics: "一句", syncedLyrics: null },
        ]);
      }
      if (url.host === "api.anthropic.com") {
        aiCalls++;
        return Response.json({
          id: `msg_${aiCalls}`,
          type: "message",
          role: "assistant",
          model: "claude-opus-5-5",
          content: [{ type: "text", text: JSON.stringify(annotation) }],
          stop_reason: "end_turn",
          stop_details: null,
          stop_sequence: null,
          usage: { input_tokens: 1, output_tokens: 1 },
        });
      }
      throw new Error(`unexpected fetch ${url}`);
    }),
  );
});

afterEach(() => vi.unstubAllGlobals());

function identityToken(claims: { iss: string; aud: string; sub?: string; email?: string; email_verified?: unknown }, expiresIn = "10m") {
  return new SignJWT({ email: claims.email, email_verified: claims.email_verified })
    .setProtectedHeader({ alg: "RS256", kid: "k1" })
    .setIssuer(claims.iss)
    .setAudience(claims.aud)
    .setSubject(claims.sub ?? "user-1")
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(keys.privateKey);
}

function call(method: string, path: string, opts: { body?: unknown; session?: string; appToken?: string } = {}, e = env) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (opts.session) headers.Authorization = `Bearer ${opts.session}`;
  if (opts.appToken) headers["X-App-Token"] = opts.appToken;
  return handle(
    new Request(`https://api.test${path}`, {
      method,
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    }),
    e,
    deps,
  );
}

async function signIn(provider: "apple" | "google", idToken: string, e = env) {
  return call("POST", "/auth/signin", { body: { provider, idToken } }, e);
}

async function googleSession(sub = "user-1") {
  const res = await signIn(
    "google",
    await identityToken({ iss: "https://accounts.google.com", aud: "123-abc.apps.googleusercontent.com", sub, email: "a@b.c", email_verified: true }),
  );
  return ((await res.json()) as any).sessionToken as string;
}

describe("POST /auth/signin", () => {
  it("exchanges a valid Apple identity token for a session", async () => {
    const res = await signIn(
      "apple",
      await identityToken({ iss: "https://appleid.apple.com", aud: "com.kevindai.musicsheet", sub: "000123.abc", email: "x@privaterelay.appleid.com", email_verified: "true" }),
    );
    expect(res.status).toBe(200);
    const body: any = await res.json();
    expect(body.user).toEqual({ id: "apple:000123.abc", email: "x@privaterelay.appleid.com" });
    expect(body.sessionToken).toBeTruthy();

    const me: any = await (await call("GET", "/auth/me", { session: body.sessionToken })).json();
    expect(me).toEqual({ user: body.user, owner: false, usage: { used: 0, limit: 2 } });
  });

  it("rejects a token for another app, an expired token, and a bad signature", async () => {
    const wrongAud = await identityToken({ iss: "https://appleid.apple.com", aud: "com.someone.else" });
    expect((await signIn("apple", wrongAud)).status).toBe(401);

    const expired = await identityToken({ iss: "https://accounts.google.com", aud: "123-abc.apps.googleusercontent.com" }, "-1m");
    expect((await signIn("google", expired)).status).toBe(401);

    const forged = await new SignJWT({}).setProtectedHeader({ alg: "HS256" }).setIssuer("https://appleid.apple.com")
      .setAudience("com.kevindai.musicsheet").setSubject("x").setExpirationTime("10m").sign(new TextEncoder().encode("guess"));
    const res = await signIn("apple", forged);
    expect(res.status).toBe(401);
    expect(((await res.json()) as any).error).toBe("invalid_identity");
  });

  it("drops an unverified email", async () => {
    const res = await signIn(
      "google",
      await identityToken({ iss: "https://accounts.google.com", aud: "123-abc.apps.googleusercontent.com", email: "a@b.c", email_verified: false }),
    );
    expect(((await res.json()) as any).user.email).toBeNull();
  });

  it("reports Google as unavailable when no client id is configured", async () => {
    const token = await identityToken({ iss: "https://accounts.google.com", aud: "123-abc.apps.googleusercontent.com" });
    const res = await signIn("google", token, { ...env, GOOGLE_CLIENT_IDS: "" });
    expect(res.status).toBe(400);
    expect(((await res.json()) as any).error).toBe("provider_unavailable");
  });
});

describe("authenticated routes", () => {
  it("require a session or the app token", async () => {
    expect((await call("POST", "/songs/generate", { body: { title: "歌" } })).status).toBe(401);
    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, session: "garbage" })).status).toBe(401);
    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, appToken: "wrong" })).status).toBe(401);
    expect((await call("GET", "/auth/me", { appToken: "owner-secret" })).status).toBe(200);
  });

  it("does not accept a session signed with another secret", async () => {
    const session = await googleSession();
    const res = await call("GET", "/auth/me", { session }, { ...env, SESSION_SECRET: "rotated" });
    expect(res.status).toBe(401);
  });

  it("limits each signed-in user per day, counting only successful generations", async () => {
    const alice = await googleSession("alice");
    const bob = await googleSession("bob");

    // A lyrics miss costs nothing.
    vi.mocked(fetch).mockImplementationOnce(async () => Response.json([]));
    vi.mocked(fetch).mockImplementationOnce(async () => Response.json({ result: { songs: [] } }));
    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, session: alice })).status).toBe(404);

    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, session: alice })).status).toBe(200);
    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, session: alice })).status).toBe(200);
    const over = await call("POST", "/songs/generate", { body: { title: "歌" }, session: alice });
    expect(over.status).toBe(429);
    expect(((await over.json()) as any).error).toBe("quota_exceeded");

    expect((await call("POST", "/songs/generate", { body: { title: "歌" }, session: bob })).status).toBe(200);
    // The owner token is not limited.
    for (let i = 0; i < 3; i++) {
      expect((await call("POST", "/songs/generate", { body: { title: "歌" }, appToken: "owner-secret" })).status).toBe(200);
    }
    const me: any = await (await call("GET", "/auth/me", { session: alice })).json();
    expect(me.usage).toEqual({ used: 2, limit: 2 });
  });

  it("forgets a user's usage when the account is deleted", async () => {
    const alice = await googleSession("alice");
    await call("POST", "/songs/generate", { body: { title: "歌" }, session: alice });
    expect((await call("DELETE", "/auth/account", { session: alice })).status).toBe(200);
    const me: any = await (await call("GET", "/auth/me", { session: alice })).json();
    expect(me.usage.used).toBe(0);
  });
});
