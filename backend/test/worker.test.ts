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

function openAIResponse(body: unknown, overrides: Record<string, unknown> = {}) {
  return {
    id: "resp_1",
    object: "response",
    created_at: 0,
    status: "completed",
    model: "gpt-5.5",
    output: [
      {
        type: "message",
        id: "msg_1",
        status: "completed",
        role: "assistant",
        content: [{ type: "output_text", text: JSON.stringify(body), annotations: [] }],
      },
    ],
    incomplete_details: null,
    usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
    ...overrides,
  };
}

const lrclibTrack = {
  trackName: "测试歌",
  artistName: "某歌手",
  albumName: null,
  duration: 200,
  instrumental: false,
  plainLyrics: "第一句\n第二句",
  syncedLyrics: "[00:10.00]第一句\n[00:15.00]第二句",
};

/** Stubs fetch: LRCLIB returns the fixture; AI hosts are answered by `ai`. Records which AI hosts were called. */
function stubNetwork(ai: (host: string, req: Request) => Promise<Response>) {
  const aiHosts: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const req = new Request(input, init);
      const { host } = new URL(req.url);
      if (host === "lrclib.net") return Response.json([lrclibTrack]);
      aiHosts.push(host);
      return ai(host, req);
    }),
  );
  return aiHosts;
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

describe("lyrics provider failures", () => {
  it("reports 502 lyrics_unavailable, not 404, when every provider errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = new URL(input instanceof Request ? input.url : String(input));
        if (url.host === "lrclib.net") throw new TypeError("fetch failed");
        return new Response("blocked", { status: 403 });
      }),
    );
    const res = await generate({ title: "晴天" });
    expect(res.status).toBe(502);
    const body: any = await res.json();
    expect(body.error).toBe("lyrics_unavailable");
    expect(body.detail).toHaveLength(2);
  });

  it("still says not found when one provider answered and the other failed", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = new URL(input instanceof Request ? input.url : String(input));
        if (url.host === "lrclib.net") return Response.json([]);
        throw new TypeError("fetch failed");
      }),
    );
    expect((await generate({ title: "x" })).status).toBe(404);
  });
});

describe("AI provider selection", () => {
  const both: Env = { ...env, OPENAI_API_KEY: "sk-openai-test" };
  const answer = async (host: string) =>
    host === "api.openai.com" ? Response.json(openAIResponse(annotation)) : Response.json(claudeMessage(annotation));

  function generateWith(e: Env, body: unknown) {
    return worker.fetch(
      new Request("https://api.test/songs/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-App-Token": "secret" },
        body: JSON.stringify(body),
      }),
      e,
    );
  }

  it("uses OpenAI with the shared prompt and schema when only an OpenAI key is set", async () => {
    let openAIRequest: any;
    const hosts = stubNetwork(async (host, req) => {
      openAIRequest = await req.json();
      return answer(host);
    });
    const res = await generateWith({ APP_TOKEN: "secret", OPENAI_API_KEY: "sk-openai-test" }, { title: "测试歌" });
    expect(res.status).toBe(200);
    const sheet: any = await res.json();
    expect(hosts).toEqual(["api.openai.com"]);
    expect(sheet.generatedBy).toEqual({ provider: "openai", model: "gpt-5.5" });
    expect(sheet.sections[0].lines[1].chords).toEqual([{ at: 2, chord: "G" }]);
    expect(openAIRequest.input).toContain("0\t第一句\n1\t第二句");
    expect(openAIRequest.text.format).toMatchObject({ type: "json_schema", name: "chord_annotation", strict: true });
  });

  it("prefers Anthropic when both keys are set, unless AI_PROVIDER or the request says otherwise", async () => {
    let hosts = stubNetwork(answer);
    await generateWith(both, { title: "x" });
    expect(hosts).toEqual(["api.anthropic.com"]);

    hosts = stubNetwork(answer);
    await generateWith({ ...both, AI_PROVIDER: "openai" }, { title: "x" });
    expect(hosts).toEqual(["api.openai.com"]);

    hosts = stubNetwork(answer);
    const res = await generateWith(both, { title: "x", provider: "openai" });
    expect(hosts).toEqual(["api.openai.com"]);
    expect(((await res.json()) as any).generatedBy.provider).toBe("openai");
  });

  it("honours a custom model", async () => {
    let model = "";
    stubNetwork(async (host, req) => {
      model = ((await req.json()) as any).model;
      return answer(host);
    });
    await generateWith({ APP_TOKEN: "secret", OPENAI_API_KEY: "k", OPENAI_MODEL: "gpt-custom" }, { title: "x" });
    expect(model).toBe("gpt-custom");
  });

  it("rejects a requested provider that has no key, and reports when none is configured", async () => {
    stubNetwork(answer);
    let res = await generateWith(env, { title: "x", provider: "openai" });
    expect(res.status).toBe(400);
    expect(((await res.json()) as any).error).toBe("provider_unavailable");

    res = await generateWith({ APP_TOKEN: "secret" }, { title: "x" });
    expect(res.status).toBe(500);

    res = await generateWith(env, { title: "x", provider: "gemini" });
    expect(res.status).toBe(400);
  });

  it("maps an OpenAI refusal and a cut-off answer to provider-neutral errors", async () => {
    const openAIOnly: Env = { APP_TOKEN: "secret", OPENAI_API_KEY: "k" };
    stubNetwork(async () =>
      Response.json(
        openAIResponse(annotation, {
          output: [
            {
              type: "message",
              id: "msg_1",
              status: "completed",
              role: "assistant",
              content: [{ type: "refusal", refusal: "no" }],
            },
          ],
        }),
      ),
    );
    let res = await generateWith(openAIOnly, { title: "x" });
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: "chords_failed", code: "declined", provider: "openai" });

    stubNetwork(async () =>
      Response.json(openAIResponse(annotation, { status: "incomplete", incomplete_details: { reason: "max_output_tokens" } })),
    );
    res = await generateWith(openAIOnly, { title: "x" });
    expect(await res.json()).toMatchObject({ code: "incomplete" });
  });

  it("maps rate limits from either provider to 429", async () => {
    stubNetwork(async () => Response.json({ error: { message: "slow down" } }, { status: 429 }));
    const res = await generateWith({ APP_TOKEN: "secret", OPENAI_API_KEY: "k" }, { title: "x" });
    expect(res.status).toBe(429);
  });
});

describe("POST /songs/rearrange", () => {
  const sheet = {
    title: "测试歌",
    artist: "某歌手",
    album: null,
    durationSec: 200,
    key: "C",
    capo: 0,
    bpm: 80,
    timeSignature: "4/4",
    strumming: "D DU",
    confidence: "high",
    notes: "",
    introChords: ["C"],
    lyricsSource: { provider: "lrclib", synced: true },
    arrangement: null,
    sections: [
      { name: "主歌", lines: [{ timeMs: 10_000, text: "第一句", chords: [{ at: 0, chord: "C" }] }] },
      { name: "副歌", lines: [{ timeMs: 15_000, text: "第二句", chords: [{ at: 2, chord: "G" }] }] },
    ],
  };
  const jazz: ChordAnnotation = {
    ...annotation,
    key: "C",
    strumming: "swing",
    notes: "加入七和弦",
    // The AI tries to merge the sections; the server keeps the original ones.
    sections: [{ name: "全曲", startLine: 0 }],
    chords: [
      { line: 0, at: 0, chord: "Cmaj7" },
      { line: 1, at: 1, chord: "G7" },
    ],
  };

  function rearrange(body: unknown) {
    return worker.fetch(
      new Request("https://api.test/songs/rearrange", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-App-Token": "secret" },
        body: JSON.stringify(body),
      }),
      env,
    );
  }

  it("sends the current chords and style, keeps lyrics and sections, and marks the arrangement", async () => {
    let prompt: any;
    const hosts = stubNetwork(async (_host, req) => {
      prompt = await req.json();
      return Response.json(claudeMessage(jazz));
    });
    const res = await rearrange({ sheet, style: "爵士" });
    expect(res.status).toBe(200);
    expect(hosts).toEqual(["api.anthropic.com"]); // no lyrics lookup
    const out: any = await res.json();
    expect(out.arrangement).toEqual({ style: "爵士" });
    expect(out.strumming).toBe("swing");
    expect(out.sections).toEqual([
      { name: "主歌", lines: [{ timeMs: 10_000, text: "第一句", chords: [{ at: 0, chord: "Cmaj7" }] }] },
      { name: "副歌", lines: [{ timeMs: 15_000, text: "第二句", chords: [{ at: 1, chord: "G7" }] }] },
    ]);
    const user: string = prompt.messages[0].content;
    expect(user).toContain("目标风格：爵士");
    expect(user).toContain("0\t第一句\t0:C");
    expect(user).toContain("副歌：从第 1 行开始");
    expect(prompt.system).toContain("改编");
  });

  it("can use OpenAI", async () => {
    const hosts = stubNetwork(async () => Response.json(openAIResponse(jazz)));
    const res = await worker.fetch(
      new Request("https://api.test/songs/rearrange", {
        method: "POST",
        headers: { "X-App-Token": "secret" },
        body: JSON.stringify({ sheet, style: "民谣", provider: "openai" }),
      }),
      { ...env, OPENAI_API_KEY: "k" },
    );
    expect(res.status).toBe(200);
    expect(hosts).toEqual(["api.openai.com"]);
  });

  it("rejects a missing style or a malformed sheet", async () => {
    expect((await rearrange({ sheet, style: " " })).status).toBe(400);
    expect((await rearrange({ sheet: { ...sheet, sections: [] }, style: "爵士" })).status).toBe(400);
  });
});
