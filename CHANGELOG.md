# Changelog

本文件记录 AI Studio（Flutter）仓库的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

版本标题格式：`## [x.y.z] — yyyy-MM-dd`（方括号内为 semver；日期用 ISO；中间为 em dash `—`）。  
发版时由 `.github/scripts/extract-changelog.mjs` 按 tag（如 `v1.0.0`）截取对应章节生成 GitHub Release 正文。

应用版本以 `apps/desktop_fluent` / `apps/mobile_material` 的 `pubspec.yaml` 为准；共享包（`core` / `design_*`）当前为 `0.0.1`，随应用能力一并演进，不单独发版叙事。

---

## [Unreleased]

### Added

（暂无）

### Changed

（暂无）

### Fixed

（暂无）

---

## [1.0.4] — 2026-09-10

### Added

- **更新确认弹窗 OD 稿**：Fluent / Material × 亮暗共 4 份确认态原型（`FB-UPDATE`），总览入口已挂

### Changed

- **更新确认弹窗对齐 OD**：双端标题/文案统一；移动端抽离共用 `update_prompt_dialog`；桌面去掉无效 `installing` 态，下载中由 InfoBar + 关于页进度承接

### Fixed

- **桌面视频预览黑屏**：Windows 上 `VideoPlayer` 经 `ClipRRect` + `FittedBox(原生像素尺寸)` 时纹理常不显示（进度条仍走）；内嵌/放大播放改为 `AspectRatio` 定框直接铺纹理

---

## [1.0.3] — 2026-09-10

### Added

- **Agnes 生图协议**：`agnes-image-*` 走 size 档位（1K–4K）+ `ratio`；图生图参考图写入 `extra_body.image`；双端作曲器按活跃提供商同步 size / 比例选项
- **生图 / 生视频回合提示复制**：双端用户提示气泡可复制（桌面 Flyout / 悬浮；移动长按底栏 + SnackBar）

### Changed

- **Agnes 视频参数**：补齐 1080P / 1K 等 size、默认时长与 v2.0 推荐时长；模型识别收紧为 `agnes-video*` / `agnes-image*`，避免对话模型误入视频协议
- **提示词辅助（草稿 | 润色）**：上区改为下划线 Tab 切换；工具行按钮统一高度；「应用润色结果」与「填入」同处行尾；Material Sheet 默认约 88% 屏高贴底

### Fixed

- **提示词辅助结构化 chip 底部大块留白**：上区去掉与 chip 区争 flex 的 `Flexible`，高度跟内容封顶，剩余空间交给 chip 滚动区
- **视频预览播完首尾帧来回跳**：Windows `video_player_win` 在 `completed` 后再 `seekTo(duration)` 会强制续播；双端播放器加守卫，接近片尾主动暂停并钉住末态；进度条用墙钟插值对齐画面，钉住时强制满格

---

## [1.0.2] — 2026-09-09

### Added

- **检查更新体验完善**：冷启动 / 托盘发现更新弹窗（跳过此版本 / 稍后 / 下载并安装）；设置入口 **NEW** 角标；关于页「启动时自动检查」开关、状态 pill、changelog
- **`UpdatePrefs`**（core）：持久化 `autoCheckUpdate` / `skippedUpdateVersion` / `availableUpdateVersion`；兼容迁移旧横幅「稍后」键
- **更新说明 Markdown**：弹窗与关于页用紧凑 `MarkdownHost` 渲染（标题 / 加粗 / 列表）
- **下载可取消**：关于页下载中可取消；中断后清理临时文件且不自动重试；按钮位变为进度条

### Changed

- 更新检查默认超时 45s；下载瞬时失败最多重试 3 次；错误文案中文化
- 静默检查失败降为 warn（不刷 ERROR）；手动检查仍完整反馈
- 安装前重新拉取清单，避免长时间持有过期结果
- 关于页「下载并安装」直接开装，不再二次确认弹窗（冷启动 / 托盘仍弹确认框）

### Fixed

- 检查更新原始 Socket / Timeout 文案（如「信号灯超时时间已到」）改为可读中文
- **出站 HTTP 跟随系统代理**：无 `HTTP(S)_PROXY` 时，Windows 读取 Internet 设置（如 Clash），避免浏览器能开、应用直连超时
- **更新说明中文乱码**：GitHub 清单为 `application/octet-stream` 时强制 UTF-8 解码（不再走 `response.body` 的 latin1）

---

## [1.0.1] — 2026-09-09

### Changed

- **Material 开屏**：去掉原生 splash logo，仅保留纯色启动底；品牌展示只走 `BrandIntroGate`，避免冷启动先大 logo 再跳小卡片
- **Material 冷启动**：仅预加载外观后立即 `runApp` 播品牌首屏；其余仓库并行后台加载，就绪后再挂 `AppShell`，缩短白屏等待
- **Material 提供商**：列表选中后可直接「删除所选提供商」（内置禁用；需确认；仍保留编辑抽屉内删除）

---

## [1.0.0] — 2026-09-08

首个正式可交付版本：双端独立 UI + 共享 `packages/core`，覆盖对话 / 生图 / 生视频 / 设置与更新主路径。

### 发版摘要

- **双端可用**：Windows / macOS（Fluent）与 Android / iOS（Material 3）能力对等、UI 独立
- **核心能力**：流式对话、文生/图生图、文生/图生视频、多提供商与本机密钥、外观与日志、数据备份
- **直链更新**：桌面 `latest.json`（minisign）· Android `android-latest.json`（sha256 侧载）；更新源指向本仓 Releases
- **安装显示名**：安装后桌面快捷方式 / 开始菜单 / 移动桌面图标统一为 **AI Studio**
- **分发产物**：`AI.Studio_<version>_x64-setup.exe`（Inno）· `AI.Studio_<version>_aarch64.zip` / `_x64.zip`（macOS）· `AI.Studio_<version>_<abi>.apk`（Android 按 ABI 分包）

### Added

#### 用户功能

- **对话**：OpenAI 兼容 SSE 流式、停止 / 撤回、Markdown、会话参数覆盖、可搜索模型选择
- **生图**：文生 / 图生、时间线、灯箱、另存；移动端相册与系统分享（`share_plus`）
- **生视频**：文生 / 图生、任务进度与恢复、播放与另存；任务队列按状态筛选（全部 / 生成中 / 待恢复 / 已完成 / 失败 / 已放弃）；移动端分享
- **设置**：提供商 / 对话默认 / 外观 / 日志 / 关于五分类；日志可记录生视频 `waitJob` 轮询明细（来源 `video`）
- **桌面（Fluent）**：NavigationView 四入口、会话列表窗格、自绘无边框标题栏、系统托盘、关闭三态（Ask · Quit · Tray）、冷启动更新横幅、关于页检查更新
- **移动（Material）**：NavigationBar 四入口、会话列表页 + 全屏二级、IME 时隐藏底栏、返回托管（`BackHost`）、根页「再按一次退出」、冷启动更新横幅；Android 侧载更新；iOS 非 Store 分发说明
- **开屏**：原生静图 splash；双端冷启动短品牌首屏（可跳过，`F-BrandIntro` / `M-BrandIntro`）；OpenDesign 四套开屏静态参考
- **无障碍与抛光（P3）**：双端空态插画与短动效、scrim 与密度间距；Semantics / tooltip / 焦点 / liveRegion；移动触控目标 ≥48；WCAG 2.2 AA 自证（非第三方认证）

#### 工程与架构

- 交付分期对照 `DESIGN.md`：P0–P2 主路径已满足；P3 抛光已落地（含 a11y 全路径自证，非第三方 WCAG 认证）
- Dart workspace：`apps/desktop_fluent`、`apps/mobile_material`、`packages/core`、`packages/design_fluent`、`packages/design_material`
- Fluent / Material 分栈 token 与 Theme（亮色 Claude 向、暗色 Cursor 向；字号五档；密度 comfortable / compact）
- OpenDesign 双系统原型（`design/opendesign/`）与品牌图标源（`design/brand/`）
- 产品规格 `DESIGN.md`、安全说明 `SECURITY.md`、助手约定 `AGENTS.md`
- **CI / 发版**：`.github/workflows`（`ci` / `build` / `release`）、Windows Inno 脚本 `packaging/windows/ai-studio.iss`、清单与签名脚本（`.github/scripts/`）
- `ProviderModelsCache`、生成门闩（`canSend` / `canGenerate*`）与会话 facade 下沉 `packages/core`；双端 controller 仅保留平台 IO、banner 与 session CRUD
- **ChatSessionFacade**、**ImageSessionFacade**（generate / stop、参数 / `canGenerate` / `resolveImageBytes`）、**VideoJobFacade**（generate / stop / resume* / abandon、参数与能力、`reloadVideo` / `resolveVideoBytes`）均在 core

#### packages/core

- **对话**：OpenAI 兼容 SSE、会话持久化、上下文裁剪、`GenerationRuntime`、`ChatSessionFacade`、生成门闩
- **生图 / 生视频**：客户端、会话与资产落盘、pending 恢复、图片压缩；`ImageSessionFacade`、`VideoJobFacade`（generate / stop / resume / abandon / reload）
- **提供商**：CRUD、预设、三模型分类、连通性探测、`ProviderModelsCache`、密钥 `flutter_secure_storage`（含旧明文迁移）
- **设置**：外观、对话默认、备份导入导出与清理、存储占用估算
- **更新**：桌面清单 / minisign；Android 侧载清单 / sha256；更新横幅偏好
- **安全 / 日志 / 提示词**：`url_safety`、应用日志、维度构建与 LLM 润色
- 核心单测覆盖 SSE、会话、安全存储、更新验签、备份、URL 安全、生成门闩与模型缓存等

### Changed

- 默认更新清单 URL 指向本仓 `moon-stack-OAo/Ai_Studio_Flutter` Releases
- 安装后显示名统一为 **AI Studio**（Windows 资源信息、macOS `PRODUCT_NAME`、Android `label`、iOS `CFBundleDisplayName`）；exe / `applicationId` / Dart 包名未改
- Windows Inno 安装向导支持 **English / 简体中文**；CI / release 钉 Inno Setup **6.7.3**（GitHub Releases `is-6_7_3`；旧 `files.jrsoftware.org` 直链已 404）
- 关于页文案产品化（弱化「本仓 / latest.json / minisign / sha256」等术语；桌面注明中英安装向导）
- CI：release / build 增加 Gradle 与 Inno Setup 安装包缓存，缩短重复构建时间
- **Android 分包**：发版改为 `flutter build apk --split-per-abi`；产物 `AI.Studio_<ver>_<abi>.apk`（arm64-v8a / armeabi-v7a / x86_64）；`android-latest.json` 按 ABI 分条目，客户端按设备 ABI 选包
- **macOS 发版**：Release / 预览构建增加按芯片分包：`AI.Studio_<ver>_aarch64.zip`（Apple Silicon）与 `_x64.zip`（Intel）；`latest.json` 写入 `darwin-aarch64` / `darwin-x86_64`；未做 Apple 公证（自用侧载，首次打开可能需右键「打开」）
- **Release 下载说明**：发版正文自动附带按平台/芯片/ABI 选择安装包的对照表

### Removed

- 删除未使用 Placeholder 页（桌面 `placeholder_page` / `settings_placeholder_page`，移动 `placeholder_page`）
- 移除移动端未使用的 `cupertino_icons`；桌面保留 `uses-material-design`（`flutter_markdown` 等依赖需 Material Icons）

### Fixed

- 生视频：中转提供商类型为「OpenAI 兼容」但模型为 `grok-imagine-video` 时，自动走 xAI `/videos/generations` 创建协议
- 生视频：创建/轮询响应误标 `completed`/`success` 却无 `video.url` 时继续轮询；中转无直链时回退鉴权拉 `/content`，避免「未返回可播放地址」
- 桌面设置「关于与更新」：默认 1280×820 下收紧间距并合并多余说明，避免右侧常显滚动条
- 移动：IME 底栏收起计入全面屏系统 inset；提供商编辑改为 BottomSheet；生图/生视频参数面板竖向占用压缩
- 桌面：直接退出先藏窗再 abort/销毁，改善关闭体感；去掉切页淡入避免叠动画感

### Security

- API Key 与元数据分离；密钥存 OS 凭据库（`flutter_secure_storage`）；备份默认不含密钥
- 日志脱敏加强（`applySecretRedaction`）：query/fragment 的 `key`/`token`/`api_key`/`access_token`/`secret` 等、`Authorization` header、常见厂商 token 前缀；`sanitizeLogMessage` 与 `sanitizeErrorText` 共用同一套规则
- 更新包失败安全：缺签名 / 验签失败删除临时文件并阻断安装（桌面 minisign；Android sha256）
- 出站 URL 硬拦云元数据与明显 SSRF 靶点（详见 `SECURITY.md`）

### Notes / Known Issues

- 不上架应用商店；Linux 桌面不在首期验收范围
- Release 需配置 Secrets：`TAURI_SIGNING_PRIVATE_KEY`（必填）；可选 `ANDROID_KEY_*`
- Android 走侧载清单更新；iOS 仅提供非 Store 分发说明（无应用内自动安装更新）
- macOS 安装包为未公证 zip；Intel 构建依赖 `macos-15-intel` runner（官方计划约用至 2027-08）
- `docs/architecture.md` 部分描述可能滞后于实现，以代码与本 Changelog 为准
