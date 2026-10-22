# music-sheet

配合 LiberLive C2 练琴的 iPhone App：输入歌名，自动获取歌词，由 Claude 标注调、速度和和弦，并支持滚动跟练。

## 计划

1. **后端：歌词抓取 + AI 配和弦**（`backend/`）
2. **iPhone App**（`ios/`，SwiftUI，先不连吉他）：生成曲谱、本地曲库、改和弦、变调、级数显示、自动滚动
3. AI 风格改编：按指定风格重新配和弦，与原版并存
4. 连接 LiberLive C2：逆向蓝牙协议，把和弦推送到吉他

## 目录

- `backend/`：Cloudflare Worker，提供 `POST /songs/generate`。说明见 [backend/README.md](backend/README.md)。
- `ios/`：iPhone App。说明见 [ios/README.md](ios/README.md)。
