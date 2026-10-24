// Node.js entry point, used by the Docker image. Reads configuration from environment variables.
import { serve } from "@hono/node-server";
import { handle, type Env } from "./index";

const env: Env = {
  APP_TOKEN: process.env.APP_TOKEN ?? "",
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  ANTHROPIC_MODEL: process.env.ANTHROPIC_MODEL,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY,
  OPENAI_MODEL: process.env.OPENAI_MODEL,
  AI_PROVIDER: process.env.AI_PROVIDER,
};
if (!env.APP_TOKEN) console.warn("APP_TOKEN is not set: every request will be rejected");

const port = Number(process.env.PORT ?? 8080);
serve({ fetch: (request) => handle(request, env), port }, (info) => {
  console.log(`music-sheet-api listening on :${info.port}`);
});
