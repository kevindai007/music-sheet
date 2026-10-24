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

## 登录与用量

App 用 Apple 或 Google 登录，后端只负责验证：

1. App 拿到 Apple/Google 签发的身份令牌（JWT），调用 `POST /auth/signin`，请求体为 `{"provider": "apple" | "google", "idToken": "..."}`。
2. 后端用 Apple/Google 公开的公钥验证签名、签发方和受众（Apple 是 bundle id `APPLE_BUNDLE_ID`，Google 是 `GOOGLE_CLIENT_IDS` 里的客户端 ID），然后返回自己签发的会话令牌 `{sessionToken, expiresAt, user}`，有效期 30 天，用 `SESSION_SECRET` 签名。
3. 之后的请求带上 `Authorization: Bearer <sessionToken>`。

每个登录用户每天（UTC）最多调用 `DAILY_LIMIT` 次 AI（默认 20 次）。只有成功的生成和改编才计数，用完后返回 `429 quota_exceeded`。计数保存在 `USAGE_FILE` 里，Docker 镜像默认放在 `/data` 卷。

`X-App-Token: <APP_TOKEN>` 是开发者通道，不受次数限制，供本地调试和 Debug 版 App 使用。

其他接口：
- `GET /auth/me`：当前用户和今日用量。
- `DELETE /auth/account`：删除账号。服务器上只保存了用量计数，删除后一并清掉。

## 接口

`POST /songs/generate`，需要登录（见上）。

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

### `POST /songs/rearrange`

把 App 里现有的曲谱（包括你手动改过的和弦）连同风格描述发给 AI，按新风格重新配和弦。歌词、时间轴和段落划分保持不变，只改和弦、节奏型，必要时会换调。

```json
{ "sheet": { "...": "完整的 SongSheet" }, "style": "爵士：多用七和弦和二五一", "provider": "openai" }
```

返回新的 `SongSheet`，其中 `arrangement` 为 `{ "style": "..." }`（原版曲谱的 `arrangement` 是 `null`）。

### 错误码

`401` 未登录、登录过期或 token 不对，`400` 参数错误或指定的 provider 没配 key，`404` 找不到歌词，`429` AI 限流，`500` 一个 AI key 都没配，`502` AI 调用失败（返回体里的 `code` 说明原因：`declined` / `incomplete` / `invalid_output` / `upstream`）。

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

## 部署到自己的服务器（Docker）

`Dockerfile` 会把后端打包成一个 Node.js 服务（入口 `src/server.ts`），监听 8080 端口，配置全部来自环境变量（和上面的表格一样，另有可选的 `PORT`）。

推送到 `main` 后，`.github/workflows/deploy.yml` 会：

1. 构建镜像并推送到 `ghcr.io/kevindai007/music-sheet/music-sheet-api`；
2. 通过 SSH 登录服务器，写入 `~/music-sheet-api.env`，删除旧的 story-teller 容器和上一版 music-sheet-api 容器，启动新容器（`--restart unless-stopped`，只绑定 `127.0.0.1:8080`，由 nginx 的 `app.kevinonline.org` 对外提供 HTTPS），并检查 `/health`。

生成曲谱可能要一分钟左右，nginx 默认 60 秒超时，需要在 `app.kevinonline.org` 的 `location` 里加上 `proxy_read_timeout 180s;`。

也可以在 GitHub 的 Actions 页面手动运行 "Deploy backend"。

需要在仓库的 **Settings → Environments → `oracle-node1`** 里配置：

| 名称 | 类型 | 说明 |
|---|---|---|
| `PROD_HOST` / `PROD_USER` / `PROD_SSH_KEY` | Secret | 和 story-teller 仓库里的一样 |
| `APP_TOKEN` | Secret | 开发者通道的 token，Debug 版 App 内置 |
| `SESSION_SECRET` | Secret | 可选。不填时由服务器在第一次部署时生成，保存在 `~/music-sheet-session.secret` |
| `GOOGLE_CLIENT_IDS` | Variable | Google iOS 客户端 ID，多个用逗号分隔；不填则关闭 Google 登录 |
| `DAILY_LIMIT` | Variable | 可选，每人每天的 AI 次数，默认 20 |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | Secret | 至少一个 |
| `AI_PROVIDER` / `ANTHROPIC_MODEL` / `OPENAI_MODEL` | Variable | 可选 |

本地试跑镜像：

```bash
docker build -t music-sheet-api backend
docker run --rm -p 8080:8080 --env-file backend/.dev.vars music-sheet-api
```

## 部署到 Cloudflare Workers（可选）

```bash
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY   # 和/或 OPENAI_API_KEY
npx wrangler secret put APP_TOKEN
npx wrangler secret put SESSION_SECRET
npm run deploy
```
