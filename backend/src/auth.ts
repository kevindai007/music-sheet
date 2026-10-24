import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTPayload, type JWTVerifyGetKey } from "jose";
import { z } from "zod";

export interface AuthEnv {
  /** Owner/developer token sent in X-App-Token. Not limited by the daily quota. */
  APP_TOKEN?: string;
  /** HMAC key for the session tokens this server issues. Sign-in is disabled without it. */
  SESSION_SECRET?: string;
  /** Audience of Sign in with Apple identity tokens: the app's bundle id. */
  APPLE_BUNDLE_ID?: string;
  /** Comma-separated Google OAuth client ids whose ID tokens are accepted. Google sign-in is off when empty. */
  GOOGLE_CLIENT_IDS?: string;
}

export const IDENTITY_PROVIDERS = ["apple", "google"] as const;
export type IdentityProvider = (typeof IDENTITY_PROVIDERS)[number];

export type Caller = { kind: "owner" } | { kind: "user"; id: string; email: string | null } | { kind: "anonymous" };

export class AuthError extends Error {
  constructor(
    message: string,
    readonly code: "unauthorized" | "invalid_identity" | "provider_unavailable",
  ) {
    super(message);
  }
}

const DEFAULT_APPLE_BUNDLE_ID = "com.kevindai.musicsheet";
const SESSION_ISSUER = "music-sheet";
const SESSION_TTL_SEC = 30 * 24 * 3600;

const ISSUERS: Record<IdentityProvider, string[]> = {
  apple: ["https://appleid.apple.com"],
  google: ["https://accounts.google.com", "accounts.google.com"],
};

// Fetched lazily and cached by jose, so key rotation at Apple/Google is picked up automatically.
const KEYS: Record<IdentityProvider, JWTVerifyGetKey> = {
  apple: createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys")),
  google: createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs")),
};

function audiences(provider: IdentityProvider, env: AuthEnv): string[] {
  if (provider === "apple") return [env.APPLE_BUNDLE_ID || DEFAULT_APPLE_BUNDLE_ID];
  return (env.GOOGLE_CLIENT_IDS ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);
}

function sessionKey(env: AuthEnv): Uint8Array {
  if (!env.SESSION_SECRET) throw new AuthError("服务器没有配置登录。", "provider_unavailable");
  return new TextEncoder().encode(env.SESSION_SECRET);
}

const IdentityClaims = z.object({
  sub: z.string().min(1),
  email: z.string().optional(),
  // Apple sends these as strings, Google as booleans.
  email_verified: z.union([z.boolean(), z.enum(["true", "false"])]).optional(),
});

/** Checks an Apple or Google identity token and returns the stable user id it vouches for. */
export async function verifyIdentityToken(
  provider: IdentityProvider,
  idToken: string,
  env: AuthEnv,
): Promise<{ id: string; email: string | null }> {
  const audience = audiences(provider, env);
  if (audience.length === 0) throw new AuthError(`服务器没有开启 ${provider} 登录。`, "provider_unavailable");

  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(idToken, KEYS[provider], { issuer: ISSUERS[provider], audience }));
  } catch {
    throw new AuthError("登录凭证无效或已过期，请重新登录。", "invalid_identity");
  }
  const claims = IdentityClaims.safeParse(payload);
  if (!claims.success) throw new AuthError("登录凭证缺少用户信息。", "invalid_identity");
  const verified = claims.data.email_verified === true || claims.data.email_verified === "true";
  return { id: `${provider}:${claims.data.sub}`, email: verified ? (claims.data.email ?? null) : null };
}

export async function issueSession(user: { id: string; email: string | null }, env: AuthEnv) {
  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_TTL_SEC;
  const token = await new SignJWT({ email: user.email })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(SESSION_ISSUER)
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(expiresAt)
    .sign(sessionKey(env));
  return { sessionToken: token, expiresAt: new Date(expiresAt * 1000).toISOString() };
}

/** Works out who is calling: a signed-in user (Bearer session token) or the owner (X-App-Token). */
export async function authenticate(request: Request, env: AuthEnv): Promise<Caller> {
  const bearer = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (bearer) {
    try {
      const { payload } = await jwtVerify(bearer, sessionKey(env), { issuer: SESSION_ISSUER, algorithms: ["HS256"] });
      if (!payload.sub) throw new Error("missing sub");
      return { kind: "user", id: payload.sub, email: typeof payload.email === "string" ? payload.email : null };
    } catch {
      throw new AuthError("登录已过期，请重新登录。", "unauthorized");
    }
  }
  const appToken = request.headers.get("X-App-Token");
  if (env.APP_TOKEN && appToken === env.APP_TOKEN) return { kind: "owner" };
  throw new AuthError("请先登录。", "unauthorized");
}
