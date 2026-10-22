import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import type { ChordAnnotation } from "../src/types";

const env: Env = { ANTHROPIC_API_KEY: "sk-ant-test", APP_TOKEN: "secret" };

const annotation: ChordAnnotation = {
  key: "C",
  capo: 0,
  bpm: 80,
  timeSignature: "4/4",
  strumming: "",
  confidence: "high",
  notes: "",
  introChords: ["C"],
  sections: [{ name: "主歌", startLine: 0 }],
  chords: [
    { line: 0, at: 0, chord: "C" },
    { line: 1, at: 2, chord: "G" },
  ],
};

function claudeMessage(body: unknown) {
  return {
    id: "msg_1",
    type: "message",
    role: "assistant",
    model: "claude-opus-5-5",
    content: [{ type: "text", text: JSON.stringify(body) }],
    stop_reason: "end_turn",
    stop_details: null,
    stop_sequence: null,
    usage: { input_tokens: 1, output_tokens: 1 },
  };
}

function generate(body: unknown, token = "secret") {
  return worker.fetch(
    new Request("https://api.test/songs/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-App-Token": token },
      body: JSON.stringify(body),
    }),
    env,
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("POST /songs/generate", () => {
  it("rejects requests without the app token", async () => {
    const res = await generate({ title: "x" }, "wrong");
    expect(res.status).toBe(401);
  });

  it("validates the body", async () => {
    const res = await generate({ title: "" });
    expect(res.status).toBe(400);
  });

  it("fetches lyrics, sends only numbered lines to Claude, and returns a sheet", async () => {
    let claudeRequest: any;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const req = new Request(input, init);
        const url = new URL(req.url);
        if (url.host === "lrclib.net") {
          return Response.json([
            {
              trackName: "测试歌",
              artistName: "某歌手",
              albumName: null,
              duration: 200,
              instrumental: false,
              plainLyrics: "第一句\n第二句",
              syncedLyrics: "[00:10.00]第一句\n[00:15.00]第二句",
            },
          ]);
        }
        if (url.host === "api.anthropic.com") {
          claudeRequest = await req.json();
          expect(req.headers.get("anthropic-beta")).toContain("server-side-fallback-2026-07-01");
          return Response.json(claudeMessage(annotation));
        }
        throw new Error(`unexpected fetch ${url}`);
      }),
    );

    const res = await generate({ title: "测试歌", artist: "某歌手" });
    expect(res.status).toBe(200);
    const sheet = await res.json();
    expect(sheet).toMatchObject({
      title: "测试歌",
      key: "C",
      lyricsSource: { provider: "lrclib", synced: true },
      sections: [
        {
          name: "主歌",
          lines: [
            { timeMs: 10_000, text: "第一句", chords: [{ at: 0, chord: "C" }] },
            { timeMs: 15_000, text: "第二句", chords: [{ at: 2, chord: "G" }] },
          ],
        },
      ],
    });
    expect(claudeRequest.model).toBe("claude-opus-5-5");
    expect(claudeRequest.fallbacks).toBe("default");
    expect(claudeRequest.messages[0].content).toContain("0\t第一句\n1\t第二句");
  });

  it("falls back to NetEase when LRCLIB has nothing, and 404s when no provider does", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = new URL(input instanceof Request ? input.url : String(input));
        if (url.host === "lrclib.net") return Response.json([]);
        if (url.pathname.startsWith("/api/search")) return Response.json({ result: { songs: [] } });
        throw new Error(`unexpected fetch ${url}`);
      }),
    );
    const res = await generate({ title: "不存在的歌" });
    expect(res.status).toBe(404);
    expect(vi.mocked(fetch)).toHaveBeenCalledTimes(2);
  });
});
