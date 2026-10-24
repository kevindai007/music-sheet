import type { Lyrics } from "../types";

// Shared by every provider so they all get the same task and return the same shape.
export const SYSTEM_PROMPT = `你是一位资深的吉他编曲老师，帮助学生为流行歌曲配和弦。

你会收到一首歌的歌名、歌手和按行编号的歌词。请给出与原唱录音一致的调、速度和和弦走向。

规则：
- 和弦要尽量贴合原唱录音，而不是随意的简化版本。不确定时，把 confidence 设为 medium 或 low，并在 notes 中说明。
- 只通过行号（line）和行内字符位置（at，从 0 开始，按字计算）标出和弦变化的位置。不要在输出中重复或改写任何歌词。
- 每个和弦标在和弦变化落下的那个字上。一行可以有多个和弦，也可以没有。
- key 写原唱的调。如果原调对吉他手不友好，可以建议 capo，但和弦仍按实际发声的调来写。
- 用中文给出段落名称（主歌、副歌、桥段等）和简短的练习提示。`;

export function buildUserPrompt(lyrics: Lyrics): string {
  const numbered = lyrics.lines.map((l, i) => `${i}\t${l.text}`).join("\n");
  return [
    `歌名：${lyrics.title}`,
    `歌手：${lyrics.artist}`,
    lyrics.album ? `专辑：${lyrics.album}` : null,
    "",
    "歌词（行号<TAB>歌词）：",
    numbered,
  ]
    .filter((s) => s !== null)
    .join("\n");
}
