# AGENTS.md — macOS 端

Swift + SwiftUI（Liquid Glass）的 Pterosaur 原生客户端，**自带内核**（ADR-064）：本应用不依赖自托管
server 即可完整使用；server 只在用户选择「云同步」时作为同步中枢。

协议层的规格与样例全部来自仓库根 `packages/contract/` 与 `docs/`——本目录只放实现。

## 目录

```
apps/macos/
├─ Package.swift         SwiftPM 清单：Core（纯逻辑）/ App（可执行）/ TestSupport / SelfTest
├─ Core/                 协议层与模型（引擎无关的纯 Swift，可单测）
│  └─ Sources/
│     ├─ Crypto/         MD5 / SHA-1 / SHA-256 / PBKDF2 / AES / RSA / UTF-8（对拍 contract/vectors）
│     ├─ Net/            同步 HTTP、瞬时故障重试、Set-Cookie 收敛、TTL+LRU 缓存、fMP4 采样率解析
│     ├─ Netease/        签名与接口、归一化、内容能力、播放与歌词、扫码登录与设备身份（ADR-053 纯算法）
│     ├─ Bilibili/       搜索、dash.audio、分P / 磁带、字幕歌词、wbi 签名、扫码登录
│     └─ Model/          Track / Artist / Album / Playlist / Lyric（对应 shared/types.ts）
├─ TestSupport/          自测用例（读 ../../packages/contract/**）+ 本端黄金快照夹具 Fixtures/
├─ SelfTest/             自测入口（`swift run selftest`）
└─ App/                  SwiftUI 外壳：AppState / 路由、播放（AVPlayer）、资料库（JSON）、Keychain、登录弹窗
```

`Core` 与 `App` 之间只通过协议交互——`Core` 不 import SwiftUI / AVFoundation / WebKit。

## 铁律

- **只有 Core 可以请求上游**。UI 层不得出现 `URLSession` 或上游域名（对应 Web 端的「同源代理铁律」，ADR-064）。
  唯一例外是封面图（`RemoteImage`）——CDN 直链，不经协议层。
- **Core 的契约测试必须读 `packages/contract`**，不得把样例复制进来。
- **改协议 = 同一提交里改 `packages/contract`**（ADR-065 / ADR-069）。
- **`LibraryData` 的未知字段必须原样回写**：云同步是整份覆盖（ADR-038），解码时丢弃未知字段再回写
  会抹掉其它端写入的内容。Swift 的 `Codable` 默认丢字段——persisted 模型须自定义解码与编码保留未知键。
- 播放地址一律 https；封面按 CDN 规范化（网易云 `canonicalNeteaseImage` 的 Swift 版、B 站 `i0`–`iN` 归一）。
- 扫码登录：二维码由 SwiftUI 画（内核只给 URL）；会话 cookie 存 Keychain，退出登录一并清理。
  设备身份优先用 ADR-053 的纯算法；兜底可用隐藏 `WKWebView` 跑官方 SDK。

## 视觉：Liquid Glass（ADR-070）

- **最低系统 macOS 26**：外壳按 Liquid Glass 设计，`glassEffect` / `GlassEffectContainer` / `buttonStyle(.glassProminent)` 只能部署到 26；`Package.swift` 的平台版本与此绑定，不要随手调回 15。
- **玻璃只给「浮在内容之上」的东西**：播放条、主操作按钮、可交互的图标钮、账号入口。内容层（列表、封面、hero）铺在背景上、不套玻璃——满屏玻璃等于没有层级。
- 底座是 `AppBackground`（主题渐变 + 当前曲封面代表色，`ArtColorLoader` 取色）；玻璃要有可折射的内容才成立，别把根视图背景画成纯色。
- 列表一律 `listStyle(.plain)` + `scrollContentBackground(.hidden)` + `listRowBackground(Color.clear)`，让背景透上来。
- 播放条是 `.safeAreaInset(edge: .bottom)` 里的悬浮块，不是一条贴边栏；控制键放进 `GlassEffectContainer` 让相邻玻璃自然融合。
- 颜色只承载状态（正在播放 / 收藏 / 错误），不要拿颜色做装饰。

## 构建与自测

```bash
swift run selftest          # 自测：契约向量 / 黄金快照 / 纯逻辑 / 假网络用例（命令行工具链即可）
swift build                 # 全量构建，App 外壳需要完整 Xcode（SwiftUI 宏不在命令行工具链里）
```

**不用 `swift test` / XCTest**：本仓只在 Xcode 命令行工具（CLT）下开发，CLT 不带 XCTest，测试 target
根本编不过。自测因此是普通可执行 target（`SelfTest/main.swift` → `TestSupport/SelfTest.swift` 的用例清单），
失败返回非零退出码。新增用例：在 `TestSupport/` 加文件，并在 `SelfTest.runAll()` 的清单里登记。

黄金快照 `TestSupport/Fixtures/golden-observed.json` 是本端归一化实现逐条跑 `golden/normalize.json` 的输出；
契约或归一化实现变更后需重新生成（同时核对快照里的 `expected` 与契约原文一致）。

Windows 上无法构建本端；CI 的 macOS runner 负责 `swift run selftest` 与 `swift build --product Pterosaur`
（`.github/workflows/all.yml` 的 `macos` job）。

## 功能范围

- 支持：发现 / 搜索 / 歌单 / 艺人 / 专辑 / 磁带（B 站）/ 播放队列 / 全屏歌词 / 资料库 / 登录（扫码 + 自提供 Cookie）。
- **不支持**：CD 刻录（ADR-064 已定）；PWA 外壳缓存（Web 专属）。
- 待定：翻录的数字打包（ZIP）是否进入本端。
- 当前状态：Core 的网易云 / B 站能力（搜索、发现、歌单·磁带详情、艺人、专辑、播放地址与音质、歌词、
  仪表登录接口）已全部落地并有假网络用例；设备身份（ADR-053 纯算法）尚未接入（`NullNeteaseDevice`），
  扫码 803 之前一切正常，手机确认后会命中 8821 设备风控。外壳已有：侧栏 / 发现 / 搜索 / 歌单与磁带详情 /
  艺人 / 专辑 / 排行榜 / 资料库（我喜欢 · 最近 · 收藏 · 本地歌单）/ 播放队列 / 播放条 / 歌词面板 /
  登录弹窗（扫码 + 自提供 Cookie）/ Keychain 会话。云同步与翻录未做。

## 发版

按路径打 tag：`macos/v<版本>`。