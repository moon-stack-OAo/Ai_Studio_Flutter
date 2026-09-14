# Architecture

实现架构说明。**产品规格以根目录 [`DESIGN.md`](../DESIGN.md) 为准**；安全细则见 [`SECURITY.md`](../SECURITY.md)。本文只描述仓库落点与模块关系，不替代能力表。

## 1. 工程落点与红线

```text
apps/desktop_fluent/     # Windows + macOS · Fluent UI
apps/mobile_material/    # Android + iOS · Material 3 UI
packages/core/           # 无 UI：协议 / SSE / adapter / 存储 / 更新 / 备份 / 日志
packages/design_fluent/  # Fluent token、Theme、基础壳件
packages/design_material/# Material token、Theme、基础壳件
design/opendesign/       # OD 原型权威源（对照 DESIGN 验收）
```

红线（与 `AGENTS.md` / `DESIGN.md` 一致）：

- **只共享业务**进 `packages/core`；`design_fluent` ↔ `design_material`、两套 app **禁止互相 import Widget**。
- 亮色 Claude 向、暗色 Cursor 向；亮暗 primary hue 不得共用。
- 字体分栈：Fluent=Segoe 系；Material=Roboto/Noto 系；不内嵌商业正文字库。
- 不上架；更新走直链 / 侧载清单（本仓 Releases）。
- 能力对等 ≠ UI 同构：同一能力 ID 两端各自实现，不抽「换皮通用 Widget」。

## 2. 包边界

| 包 / 应用 | 可放 | 不可放 |
|-----------|------|--------|
| `packages/core` | 协议、SSE、OpenAI 兼容 client、提供商/会话/生图/生视频状态、安全存储、`url_safety`、更新客户端、备份、日志、播放偏好/错误文案、封面缓存逻辑 | Flutter Widget、主题 token、任一设计系统控件 |
| `packages/design_fluent` | Fluent token、Theme、确认框等共享壳件 | 业务 API、会话持久化、Material Widget |
| `packages/design_material` | Material token、Theme、确认框等共享壳件 | 业务 API、会话持久化、Fluent Widget |
| `apps/desktop_fluent` | 桌面页面、导航、托盘、窗口、单实例、桌面插件接线（`window_manager` / `tray_manager` / `media_kit`） | import Material 侧 Widget；可复用业务堆在 app 不下沉 |
| `apps/mobile_material` | 移动页面、底栏、相册/分享、返回托管、`media_kit` 推页播放 | import Fluent 侧 Widget；可复用业务堆在 app 不下沉 |

依赖方向（概念）：

```text
apps/*  →  design_*（本端） + core
design_* → （无业务依赖；不依赖 apps）
core     → （无 Flutter UI；可依赖 foundation / 平台无关库）
```

## 3. 提供商与密钥

规格：`DESIGN.md` §5.7；安全与迁移：`SECURITY.md`「密钥存储」。

| 概念 | 落点 |
|------|------|
| 模型配置 | `ProviderConfig`（id / name / type / baseUrl / apiKey / chat·image·videoModel / enabled / builtin） |
| CRUD / 选中 / 活跃凭证 | `ProviderRepository` → `activeChatCredentials` 等 |
| 元数据 | `shared_preferences` 键 `core.providers.v1`（**不含** apiKey） |
| 密钥 | `flutter_secure_storage` 键 `core.provider.keys.v1`（`SecureProviderStorage` + `SecretStore`） |
| 连通性 | `ProviderConnectionTester`（默认 `OpenAiCompatibleConnectionTester`） |
| 三模型分类 | `classifyModelId` / `modelOptionsByKind`；UI 分端 `FilterableModelPicker` 等 |

协议 client（OpenAI 兼容，含 Agnes / xAI 等 profile）：

- 对话 SSE：`OpenAiCompatibleChatClient` + `sse_parser` → `ChatSessionFacade`
- 生图：`OpenAiCompatibleImageClient` → `ImageSessionFacade`
- 生视频：`OpenAiCompatibleVideoClient` → `VideoJobFacade`

出站 URL 一律经 `url_safety`；HTTP 经 `SafeHttpClient`（跟随系统代理等），详见 `SECURITY.md`。

## 4. 桌面窗口：托盘、关闭三态、单实例

仅 `apps/desktop_fluent`（能力 `SHELL-TRAY` / `SET-CLOSE-BEHAVIOR` / `SHELL-SINGLE`）。

### 标题栏与窗口

- `window_manager`：`TitleBarStyle.hidden`
- `FluentAppTitleBar`：拖拽区 + 自绘 min/max/close（`shell/fluent_app_title_bar.dart`）
- 启动：`shell/window_bootstrap.dart`

### 关闭三态（Ask · Quit · Tray）

- 偏好字段：`AppearanceSettings.closeBehavior`（`ask` \| `quit` \| `tray`，默认 `ask`），随外观 prefs 持久化；设置入口嵌在**关于与更新**页（非独立分类）。
- 协调器：`shell/window_close_coordinator.dart`
  - `setPreventClose(true)` 拦截系统/标题栏关闭
  - `quit` → 真正退出（可先 `GenerationRuntime.abort`）
  - `tray` → 藏窗到托盘
  - `ask` → `F-CloseConfirm`；可选「记住本次选择」写回 prefs
- 托盘：`shell/system_tray_controller.dart`（`tray_manager`）；菜单含显示 / 设置 / 检查更新 / 退出

### 单实例（`SHELL-SINGLE`）

- `shell/single_instance_guard.dart`（`flutter_single_instance`）
- **须在**窗口 / 仓库初始化**之前**握手（见 `main.dart`）
- 次进程：通知首实例后 `exit`；首实例：取消最小化 / 从托盘显示 / focus
- IPC/锁失败：降级允许启动，写入运行日志（`pendingSingleInstanceLog`），不弹模态堵死

## 5. 对话 / 生图 / 生视频

能力 ID 与状态机以 `DESIGN.md` §5.4–5.6 为准。此处只记实现落点。

### 对话

| 层 | 落点 |
|----|------|
| core | `ChatSessionFacade` / `ChatSessionRepository` / `chat_models` / `generation_runtime` |
| 桌面 | `pages/chat/*`（`message_list`、`composer`、`markdown_host`…） |
| 移动 | 对应 `pages/chat/*` |
| `CHAT-ATTACH`（已落地） | core：`chat_attach.dart`、`ChatMessage.attachments`、`persistAttachments` / `chat_image_cache`、`supportsChatVision`、multimodal parts、清理与备份 omit；桌面/移动：分端 Composer 附加 + 用户气泡缩略 + 灯箱「附图」（见 `DESIGN.md` §5.4 / §9 P5） |

### 生图

| 层 | 落点 |
|----|------|
| core | `ImageSessionFacade` / `ImageSessionRepository`；回合 `referenceImages: List<ImageRef>`（`IMG-TURN-REF`） |
| 资产 | `ImageAssetStore` / `FileImageAssetStore`；删除会话 / `SET-DATA` 一并清理 |
| UI | 分端 `image_timeline`、`image_lightbox`（灯箱角标「参考」/「结果」）、`image_composer` |

### 生视频

| 能力 | core | UI / 平台 |
|------|------|-----------|
| 任务与恢复 | `VideoJobFacade`、`video_resume`、`VideoSessionRepository` | 分端 `video_page` / `video_controller` / `video_queue` |
| `VID-TURN-REF` | 同生图：`referenceImages` 落盘 | 队列用户气泡左缩略 + 右提示词 |
| `VID-QUEUE` 封面 | `VideoPosterStore` / `VideoPosterService`；抽帧接口由 app 注入 | `media_kit_video_frame_extractor.dart`（双端） |
| `VID-PLAYER` | — | **`media_kit` + `media_kit_video` + `media_kit_libs_video`**（已替换 `video_player`）；桌面内嵌 / 放大弹窗 / 系统全屏；移动推页 + `SystemChrome` 沉浸全屏 |
| 音量 prefs | `VideoPlaybackPrefs`（键 `core.video_playback.v1`：volume 0–100 + muted） | 开播前 load；拖动/静音 debounce 写入 |
| 播放错误文案 | `VideoPlaybackErrors`（中文可读 + 弱网短原因） | 内嵌/弹窗/全屏/推页统一「重试」 |
| `VID-RERUN` | 读 item 的 prompt / 参数 / `referenceImages` | `video_controller.rerunFromItem`：回填 Composer，**不**自动提交；忙态禁用 |
| `IMG-RERUN` | 读 item 的 prompt / n / size·aspect / quality / `referenceImages` | `image_controller.rerunFromItem`：回填 Composer，**不**自动提交；忙态禁用 |
| 第三方许可 | `third_party_licenses.dart`（media_kit / libmpv / FFmpeg） | 关于页「开源许可」 |

播放生命周期：桌面弹窗独立 `Player`（关即 dispose，打开时内嵌暂停）；移动推页 pop 即 dispose。

## 6. 更新

规格 UX：`DESIGN.md` `FB-UPDATE` / `SET-ABOUT`；验签与失败安全：`SECURITY.md`「更新包签名」。

| | 桌面 | Android |
|--|------|---------|
| 清单 | `latest.json`（`kDesktopUpdateManifestUrl`） | `android-latest.json`（`kAndroidUpdateManifestUrl`） |
| 客户端 | `UpdateClient` | `AndroidUpdateClient`（复用拉取/下载，关 minisign） |
| 完整性 | `platforms.*.signature` → **minisign**（Tauri 约定；公钥钉死） | `platforms.*.sha256` → **sha256** |
| 平台键 | `windows-x86_64` 等；macOS `darwin-aarch64` / `darwin-x86_64`（`update_platform.dart`） | 按设备 ABI 选包（`arm64-v8a` / `armeabi-v7a` / `x86_64`） |
| 偏好 | `UpdatePrefs`（自动检查 / 跳过版本 / 可用版本） | 同语义 |
| UI | 冷启动·托盘确认弹窗；设置 NEW 角标；关于页进度/可取消下载 | 冷启动弹窗；底栏 Badge；关于页 |

失败安全：缺签名 / 验签失败 / sha256 不匹配 → **删除临时文件并阻断安装**（无默认 skip）。

发版：推送 `v*` tag → `.github/workflows/release.yml` 产出安装包并写两份清单。

## 7. 文档与规格对照 · 仍缺项

| 主题 | 权威 | 本文 |
|------|------|------|
| 能力 ID / 状态 / 分期 | `DESIGN.md` | 只记落点 |
| 密钥 / URL / 验签 / 备份风险 | `SECURITY.md` | §3、§6 摘要并外链 |
| CI / 发版产物命名 | `AGENTS.md`、`CHANGELOG.md` | §6 一句 |

**实现仍缺（非文档债）：** 无（`CHAT-ATTACH` 等已在对应章节落地说明）。

本文不再维护过时的「待补：依赖图 / adapter / 更新协议」清单。
