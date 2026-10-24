// Node.js entry point, used by the Docker image. Reads configuration from environment variables.
import { serve } from "@hono/node-server";
import { FileUsageStore } from "./file-usage";
import { handle, type Deps, type Env } from "./index";
import { MemoryUsageStore } from "./usage";

const env: Env = {
  APP_TOKEN: process.env.APP_TOKEN ?? "",
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  ANTHROPIC_MODEL: process.env.ANTHROPIC_MODEL,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY,
  OPENAI_MODEL: process.env.OPENAI_MODEL,
  AI_PROVIDER: process.env.AI_PROVIDER,
  SESSION_SECRET: process.env.SESSION_SECRET,
  APPLE_BUNDLE_ID: process.env.APPLE_BUNDLE_ID,
  GOOGLE_CLIENT_IDS: process.env.GOOGLE_CLIENT_IDS,
  DAILY_LIMIT: process.env.DAILY_LIMIT,
};
if (!env.SESSION_SECRET) console.warn("SESSION_SECRET is not set: Apple/Google sign-in is disabled");
if (!env.APP_TOKEN && !env.SESSION_SECRET) console.warn("Neither APP_TOKEN nor SESSION_SECRET is set: every request will be rejected");

// USAGE_FILE keeps the daily counts across restarts (the Docker image points it at a volume).
const deps: Deps = {
  usage: process.env.USAGE_FILE ? new FileUsageStore(process.env.USAGE_FILE) : new MemoryUsageStore(),
};

const port = Number(process.env.PORT ?? 8080);
serve({ fetch: (request) => handle(request, env, deps), port }, (info) => {
  console.log(`music-sheet-api listening on :${info.port}`);
});
