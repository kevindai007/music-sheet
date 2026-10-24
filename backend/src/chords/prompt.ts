import type { Lyrics, SongSheetInput } from "../types";
import { sectionStarts } from "../sheet";
import type { ChordPrompt } from "./provider";

// Prompts are shared by every provider so they all get the same task and return the same shape.

const OUTPUT_RULES = `- 只通过行号（line）和行内字符位置（at，从 0 开始，按字计算）标出和弦变化的位置。不要在输出中重复或改写任何歌词。
- 每个和弦标在和弦变化落下的那个字上。一行可以有多个和弦，也可以没有。
- 用中文给出段落名称（主歌、副歌、桥段等）和简短的练习提示。`;

const ANNOTATE_SYSTEM = `你是一位资深的吉他编曲老师，帮助学生为流行歌曲配和弦。

你会收到一首歌的歌名、歌手和按行编号的歌词。请给出与原唱录音一致的调、速度和和弦走向。

规则：
- 和弦要尽量贴合原唱录音，而不是随意的简化版本。不确定时，把 confidence 设为 medium 或 low，并在 notes 中说明。
- key 写原唱的调。如果原调对吉他手不友好，可以建议 capo，但和弦仍按实际发声的调来写。
${OUTPUT_RULES}`;

const REARRANGE_SYSTEM = `你是一位资深的吉他编曲老师，擅长把一首歌改编成不同风格。

你会收到一首歌现有的曲谱（调、速度、段落，以及每行歌词上的和弦）和学生想要的风格。请按这个风格重新配和弦。

规则：
- 歌词、行号和段落划分保持不变，只改和弦、节奏型，必要时调整调和速度。
- 改编要有这个风格的特征（和声色彩、和弦密度、节奏型），同时保持旋律能唱得上去。
- 学生用 LiberLive 无弦吉他弹奏，优先使用常见的三和弦、七和弦、挂留和弦和转位和弦，避免过于复杂的和弦。
- 如果换了调，key 写新的调，和弦按新调实际发声来写。
- notes 里用两三句话说明改编思路和弹奏要点。confidence 表示你对这个改编好听、好弹的把握。
${OUTPUT_RULES}`;

function numberedLines(lines: { text: string }[]): string {
  return lines.map((l, i) => `${i}\t${l.text}`).join("\n");
}

export function annotatePrompt(lyrics: Lyrics): ChordPrompt {
  const user = [
    `歌名：${lyrics.title}`,
    `歌手：${lyrics.artist}`,
    lyrics.album ? `专辑：${lyrics.album}` : null,
    "",
    "歌词（行号<TAB>歌词）：",
    numberedLines(lyrics.lines),
  ]
    .filter((s) => s !== null)
    .join("\n");
  return { system: ANNOTATE_SYSTEM, user };
}

export function rearrangePrompt(sheet: SongSheetInput, style: string): ChordPrompt {
  const lines = sheet.sections.flatMap((s) => s.lines);
  const sections = sectionStarts(sheet).map((s) => `${s.name || "（无名段落）"}：从第 ${s.startLine} 行开始`);
  const chordRows = lines.map((l, i) => {
    const chords = l.chords.map((c) => `${c.at}:${c.chord}`).join(" ");
    return `${i}\t${l.text}\t${chords}`;
  });

  const user = [
    `目标风格：${style}`,
    "",
    `歌名：${sheet.title}`,
    `歌手：${sheet.artist}`,
    `现有曲谱：${sheet.key} 调，${sheet.bpm} BPM，${sheet.timeSignature}，节奏型：${sheet.strumming || "未注明"}`,
    `前奏和弦：${sheet.introChords.join(" ") || "无"}`,
    "",
    "段落：",
    ...sections,
    "",
    "歌词与现有和弦（行号<TAB>歌词<TAB>字位置:和弦）：",
    ...chordRows,
  ].join("\n");
  return { system: REARRANGE_SYSTEM, user };
}
