# music-sheet 后端

一个 Cloudflare Worker。它先从网上获取歌词，再让 Claude 只返回"第几行第几个字换什么和弦"，最后合成曲谱给 App。Claude 不会输出歌词本身。

## 工作流程

1. **获取歌词**：先查 [LRCLIB](https://lrclib.net)（开放接口，大多带时间轴），没有结果时再查网易云音乐的公开网页接口。
2. **配和弦**：把歌词按行编号发给 Claude（`claude-opus-5-5`，结构化输出）。Claude 返回调、变调夹、BPM、拍号、扫弦节奏、段落起始行，以及每个和弦的 `(行号, 字位置, 和弦)`。
3. **合成曲谱**：校验和弦符号，修正越界位置，按段落分组，输出 `SongSheet`（定义见 `src/types.ts`）。

如果 Claude 的安全分类器拒绝了请求，会自动由官方推荐的备用模型重试（`fallbacks: "default"`）。

## 接口

`POST /songs/generate`，请求头需带 `X-App-Token`。

```json
{ "title": "晴天", "artist": "周杰伦" }
```

返回示例（节选）：

```json
{
  "title": "晴天", "artist": "周杰伦", "key": "G", "capo": 0, "bpm": 69,
  "timeSignature": "4/4", "strumming": "D DU UDU", "confidence": "medium",
  "introChords": ["G", "D/F#", "Em", "C"],
  "lyricsSource": { "provider": "lrclib", "synced": true },
  "sections": [
    { "name": "主歌 1", "lines": [
      { "timeMs": 29350, "text": "故事的小黄花", "chords": [{ "at": 0, "chord": "G" }, { "at": 4, "chord": "D/F#" }] }
    ] }
  ]
}
```

`at` 是行内第几个字（从 0 开始，按 Unicode 字符计）。`timeMs` 在歌词带时间轴时有值，App 可以据此和原曲同步滚动。

错误码：`401` token 不对，`400` 参数错误，`404` 找不到歌词，`429` Claude 限流，`502` Claude 调用失败。

## 本地运行

需要 Node.js 20 以上。

```bash
cd backend
npm install
cp .dev.vars.example .dev.vars   # 填入 ANTHROPIC_API_KEY 和自定义的 APP_TOKEN
npm run dev                      # 启动在 http://localhost:8787

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
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_TOKEN
npm run deploy
```
