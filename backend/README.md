# music-sheet 后端

一个 Cloudflare Worker。它先从网上获取歌词，再让 AI 只返回"第几行第几个字换什么和弦"，最后合成曲谱给 App。AI 不会输出歌词本身。

## 工作流程

1. **获取歌词**：先查 [LRCLIB](https://lrclib.net)（开放接口，大多带时间轴），没有结果时再查网易云音乐的公开网页接口。
2. **配和弦**：把歌词按行编号发给 AI（Claude 或 OpenAI，结构化输出）。AI 返回调、变调夹、BPM、拍号、扫弦节奏、段落起始行，以及每个和弦的 `(行号, 字位置, 和弦)`。
3. **合成曲谱**：校验和弦符号，修正越界位置，按段落分组，输出 `SongSheet`（定义见 `src/types.ts`）。

## AI provider

支持 Anthropic 和 OpenAI，配置哪个 key 就能用哪个，两个都配也可以。

| 配置 | 作用 |
|---|---|
| `ANTHROPIC_API_KEY` | Claude 的 key（secret） |
| `OPENAI_API_KEY` | OpenAI 的 key（secret） |
| `AI_PROVIDER` | 请求里没指定时默认用哪个：`anthropic` 或 `openai`。不填则按 Anthropic、OpenAI 的顺序，用第一个配了 key 的 |
| `ANTHROPIC_MODEL` / `OPENAI_MODEL` | 覆盖默认模型（`claude-opus-5-5` / `gpt-5.5`） |

两家共用同一份提示词（`src/chords/prompt.ts`）和同一个 zod schema（`src/types.ts`），各自用官方 SDK 的结构化输出解析，所以返回格式完全一致。新增一家只需要在 `src/chords/` 里实现 `ChordProvider` 接口，再在 `src/chords/index.ts` 里注册。

如果 Claude 的安全分类器拒绝了请求，会自动由官方推荐的备用模型重试（`fallbacks: "default"`）。

## 接口

`POST /songs/generate`，请求头需带 `X-App-Token`。

```json
{ "title": "晴天", "artist": "周杰伦", "provider": "openai" }
```

`provider` 可选（`anthropic` / `openai`），不填就用服务器的默认设置。

返回示例（节选）：

```json
{
  "title": "晴天", "artist": "周杰伦", "key": "G", "capo": 0, "bpm": 69,
  "timeSignature": "4/4", "strumming": "D DU UDU", "confidence": "medium",
  "introChords": ["G", "D/F#", "Em", "C"],
  "lyricsSource": { "provider": "lrclib", "synced": true },
  "generatedBy": { "provider": "anthropic", "model": "claude-opus-5-5" },
  "sections": [
    { "name": "主歌 1", "lines": [
      { "timeMs": 29350, "text": "故事的小黄花", "chords": [{ "at": 0, "chord": "G" }, { "at": 4, "chord": "D/F#" }] }
    ] }
  ]
}
```

`at` 是行内第几个字（从 0 开始，按 Unicode 字符计）。`timeMs` 在歌词带时间轴时有值，App 可以据此和原曲同步滚动。

错误码：`401` token 不对，`400` 参数错误或指定的 provider 没配 key，`404` 找不到歌词，`429` AI 限流，`500` 一个 AI key 都没配，`502` AI 调用失败（返回体里的 `code` 说明原因：`declined` / `incomplete` / `invalid_output` / `upstream`）。

## 本地运行

需要 Node.js 20 以上。

```bash
cd backend
npm install
cp .dev.vars.example .dev.vars   # 至少填一个 AI key，再填一个自定义的 APP_TOKEN
npm run dev                      # 启动在 http://localhost:8787（真机调试用 npm run dev:lan）

curl -X POST http://localhost:8787/songs/generate \
  -H "Content-Type: application/json" -H "X-App-Token: <你的 APP_TOKEN>" \
  -d '{"title":"晴天","artist":"周杰伦"}'
```

## 测试

```bash
npm test          # 单元测试（网络请求均为模拟）
npm run typecheck
```

## 部署

```bash
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY   # 和/或 OPENAI_API_KEY
npx wrangler secret put APP_TOKEN
npm run deploy
```
