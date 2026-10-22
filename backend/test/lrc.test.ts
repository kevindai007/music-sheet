import { describe, expect, it } from "vitest";
import { parseLrc, parsePlain } from "../src/lyrics/lrc";

describe("parseLrc", () => {
  it("parses time tags, skips metadata and credit lines, and sorts by time", () => {
    const lrc = [
      "[ar:周杰伦]",
      "[00:00.00] 作词 : 周杰伦",
      "[00:29.35]故事的小黄花",
      "[00:32.5]从出生那年就飘着",
      "[01:10.120][02:20.000]刮风这天",
      "[00:40.00]",
    ].join("\n");
    expect(parseLrc(lrc)).toEqual([
      { timeMs: 29_350, text: "故事的小黄花" },
      { timeMs: 32_500, text: "从出生那年就飘着" },
      { timeMs: 70_120, text: "刮风这天" },
      { timeMs: 140_000, text: "刮风这天" },
    ]);
  });
});

describe("parsePlain", () => {
  it("drops blank and credit lines", () => {
    expect(parsePlain("作曲：某人\n\n第一句\n 第二句 ")).toEqual([
      { timeMs: null, text: "第一句" },
      { timeMs: null, text: "第二句" },
    ]);
  });
});
