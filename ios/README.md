# music-sheet iPhone App

SwiftUI 写的练琴 App（iOS 17 以上）。现在还不连吉他。

## 功能

- **生成曲谱**：输入歌名（歌手可选），后端获取歌词并让 Claude 配和弦。生成结果保存在本机曲库里。
- **曲谱页**：和弦标在对应的字上方。可以变调、设置变调夹，也可以切换成**级数显示**（1、4、5、6m），直接对应 LiberLive 上的数字和弦键。
- **自动滚动**：歌词带时间轴时可以"跟原曲"滚动，否则"按节拍"滚动（每句的小节数和 BPM 可调）。可以 0.5× 到 1.25× 变速；点某一句跳到那里。底部会预告**下一句的和弦**。
- **改和弦**：长按某一句 → 编辑和弦。
- **AI 改编**：曲谱页右上角的魔法棒。可以选民谣、R&B、爵士、简化版等预设风格，也可以自己描述。改编版会作为一首新曲谱保存（曲库里带风格标签），原版不受影响。改编版还可以继续改编。
- **示例曲谱**：曲库为空时可以载入《小星星》，不连后端也能试用。

## 在 Mac 上运行

需要 Xcode 16 以上。

```bash
brew install xcodegen
cd ios
xcodegen            # 生成 MusicSheet.xcodeproj（这个文件不提交到仓库）
open MusicSheet.xcodeproj
```

1. 在 Xcode 里选中 MusicSheet target → Signing & Capabilities → Team 选你的 Apple ID（免费账号也可以）。
2. 先选一个 iPhone 模拟器，点运行。
3. 想装到自己的 iPhone 上：用数据线连上手机，在顶部设备列表里选它，再点运行。第一次需要在手机的"设置 → 通用 → VPN 与设备管理"里信任开发者，并打开"开发者模式"。

## 连接后端

打开 App → 左上角设置：

- **模拟器**：后端用 `npm run dev` 启动，地址填 `http://localhost:8787`。
- **你的服务器**（默认）：`https://app.kevinonline.org`，nginx 反向代理到服务器上的 8080 端口。
- **真机**：后端用 `npm run dev:lan` 启动，地址填 Mac 的局域网 IP，例如 `http://192.168.1.10:8787`（在"系统设置 → Wi-Fi → 详细信息"里查看）。第一次请求时 iPhone 会询问是否允许访问本地网络，选允许。也可以把后端部署到 Cloudflare，直接填 Worker 的 https 地址。
- **App Token**：和后端 `.dev.vars` 里的 `APP_TOKEN` 一致。

### HTTPS 说明

iOS 默认只允许 App 用 HTTPS 访问公网地址，`http://` 只放行了本机和局域网（`NSAllowsLocalNetworking`）。所以连你的服务器时，需要在服务器前面配一个带证书的域名（比如 nginx/Caddy 反向代理到 8080），App 里填 `https://你的域名`。

## 代码结构

- `MusicSheetKit/`：不依赖 UI 的逻辑（曲谱模型、和弦解析与变调、级数、滚动时间轴、后端客户端），附单元测试：`swift test --package-path MusicSheetKit`。
- `MusicSheet/`：SwiftUI 界面和 SwiftData 曲库。
- `project.yml`：XcodeGen 配置。
