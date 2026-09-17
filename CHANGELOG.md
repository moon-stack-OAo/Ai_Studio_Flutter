# Changelog

本文件记录 AI Studio（Flutter）仓库的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

版本标题格式：`## [x.y.z] — yyyy-MM-dd`（方括号内为 semver；日期用 ISO；中间为 em dash `—`）。  
发版时由 `.github/scripts/extract-changelog.mjs` 按 tag（如 `v1.0.0`）截取对应章节生成 GitHub Release 正文。

可选 **`### 用户摘要`**：写在版本标题下、工程分节（`### Added` 等）之前，3～6 条白话要点，面向最终用户、少术语；关于页优先展示该段，工程明细默认折叠。无摘要时行为与原先一致（整段 body 展示）。从 Unreleased 切出版本时请把摘要草稿裁进正式版。

应用版本以 `apps/desktop_fluent` / `apps/mobile_material` 的 `pubspec.yaml` 为准；共享包（`core` / `design_*`）当前为 `0.0.1`，随应用能力一并演进，不单独发版叙事。

---

## [Unreleased]

### 用户摘要

> 发版时裁进正式版；以下为当前草稿。

- 可配置业务 MCP：对话内工具调用需确认，轨迹可折叠查看；备份默认不含 MCP Token
- 桌面支持本地 stdio，并可粘贴 OpenCode / Cursor 风格 JSON 一键导入；手机仍仅 HTTP
- 关于页更新日志优先看白话摘要，工程细节可再展开；设置页可一键回到顶部
- 提示词辅助支持 AI 润色（多种风格）与快捷再改，草稿可直接手改
- 手机端看图可左右滑动切换同组多图；生图时间线按「今天 / 昨天」分段
- 生图失败可「重新填写」再改；对话已配置时引导直接输入，不再误推「新建会话」

### Added

- **业务 MCP（P6）**：双端受控 Client（HTTP/SSE）+ 分级授权 + 工具轨迹/授权卡；core 协议与 Facade 编排（`tools`/`tool_calls`、串行 call、上限 8）；设置页 Server CRUD / 探测 / 按 tool 覆盖；未配置横幅可忽略；备份默认 omit Bearer、清数据收口 MCP；OD 设置/对话 MCP 稿
- **桌面 stdio（P6-S）**：`transport: stdio`（command/args/cwd/env）+ `ProcessHost`；保存/探测确认后启动本机进程；移动端不注入、禁用探测；规格与安全约束见 `DESIGN` / `SECURITY`
- **MCP 配置 JSON 导入**：设置「导入 JSON」；兼容本 App `mcpServers`、OpenCode `mcp`（`type: local` 命令数组）、Cursor `command`/`args`；Bearer 入凭据库；桌面 stdio 二次确认；移动跳过 stdio
- **MCP 授权与轨迹体验**：Server 默认授权 + 单 tool 覆盖；历史/进行中工具轮聚合为可折叠卡（待授权/执行中自动展开）
- **关于页更新日志**：多版本折叠 +「用户摘要」优先展示；完整历史弹层「回到顶部」；`packages/core/assets/CHANGELOG.md` 同步
- **设置页「回到顶部」浮层**：双端各设置可滚动页滚过阈值后右下角上箭头
- **提示词 AI 润色（`IMG-PROMPT` / `VID-PROMPT-REF`）**：风格 / 流式预览 / 快捷迭代；用当前对话模型只输出提示词正文
- **`IMG-LIGHTBOX` 滑动多图（Material）**：全屏灯箱左右滑切换同组多图
- **Material 生图时间分割**：时间线「今天 / 昨天 / M/D HH:mm」
- **空态 OD 原型补齐**：Fluent / Material × 亮暗对话 / 生图 / 生视频空态稿

### Changed

- **业务 MCP 规格边界**：原「本期不做 stdio」→「移动端不做；桌面可选 stdio」；HTTP/SSE 仍为双端主路径
- **`CHAT-EMPTY` 语义**：已配置时引导输入首条消息；主区去掉「新建会话」CTA
- **内容空态可挂 CTA**；空态插画精修
- **Material 生图 / 生视频 Composer**：进入页后自动聚焦提示词
- **提示词辅助**：模板草稿可编辑；`✨ AI 润色` 火花前缀恢复
- **`IMG-RERUN` 失败文案**：「重新填写」（回填不自动提交）；Fluent 失败态对齐 OD（含右键菜单）
- **`IMG-SESSION`**：生图多会话 UI 仅 Material；Fluent 单活跃会话
- **生图质量档文案**：「低 / 标准 / 高」；生图 OD 主稿回写对齐实现
- **更新说明 Markdown 紧凑样式**；提示词润色系统提示完善

### Fixed

- **提示词辅助滚动条挡内容**：双端模板列表 / 润色预览 / 结构化 Chip / 草稿输入右侧预留约 8px，避免细滚动条压住文字
- **Fluent 对话空态稿场景切换**：修复 `.view[data-view]` 无效选择器导致未配置 / 无消息两套内容同时显示；按 `data-state` 互斥展示

---

## [1.0.6] — 2026-09-14

### 用户摘要

- 对话可附加图片一起发送，气泡里能回看附图
- 生图失败、生视频完成项可「用此提示」回填参数再改，不会自动提交
- 视频播放音量与静音会记住，下次打开仍沿用
- 对话附图与部分图生图兼容性修复（含 Grok 等）；桌面参数 chip 同行排布更整齐
- 播放器弱网/失败提示更清晰，灯箱标明「参考 / 结果」来源

### Added

- **`CHAT-ATTACH`（P5 · 对话附图）**：Composer 附加图片 → 多模态发送 → 用户气泡缩略 / 灯箱「附图」回看；非 vision 入口禁用；有图可空文；与 `*-TURN-REF` 分轨（`chat_image_cache`）；清会话/备份 omit 本地附件。OD 四端 chat 稿已同步附加入口与「附图」角标
- **`VID-RERUN`**：双端队列 / 播放器「用此提示重跑」— 回填提示词、时长/比例等参数与可读参考图；不自动提交；生成中禁用
- **`IMG-RERUN`**：双端生图时间线**失败**回合「用此提示重跑」— 回填提示词、数量/比例/质量与可读参考图；不自动提交；生成中禁用
- **`VID-PLAYER` 音量跨启动持久化（E4）**：`core.video_playback.v1`（volume + muted）；双端开播前 load、拖动/静音 debounce 写入；默认 100 / 未静音

### Changed

- **对话 Composer / `CHAT-ATTACH` 视觉对齐 OD**：气泡「附图」角标；草稿条（缩略+计数）；Material 输入 16×12 / 圆角 24、附加/发送正圆 48；Fluent 附加 36×36、底对齐、卡片 gap、单行默认高、左内边距与 placeholder 微调
- **桌面 `VID-PLAYER`**：对照 OD — 头栏摘要+元信息、空舞台引导、transport 缓冲分层与音量%；动作/transport 描边 chrome（`video_tool_chrome`）；窗内放大在动作区。仅 Fluent 内嵌；移动不跟桌面密度
- **桌面生图时间线气泡铺满**（去掉与对话同宽的 720 限宽）；桌面生图/生视频提示词输入加高（`minLines` 8 / `maxLines` 12）
- **`docs/architecture.md`（E10）**：与 1.0.5+ 现状对齐（包边界、托盘/`SHELL-SINGLE`、`media_kit` / `*-TURN-REF` / `VID-RERUN` / `IMG-RERUN`、更新验签）；仍以 `DESIGN.md` / `SECURITY.md` 为准

### Fixed

- **`CHAT-ATTACH`**：`supportsChatVision` 增加 `grok`（如 `grok-4.5`）
- **xAI / 中转图生图 400**：`openai-compatible` 且模型含 `imagine-image` 时改走 xAI JSON `/images/edits`（含 MIME 嗅探），不再误发 OpenAI multipart
- **桌面参数 chip**：生图/生视频尺寸·比例·清晰度在 Wrap 内同行排布（`HoverButton` 不再撑满整行）
- **生视频 materialize**：相对路径 `/v1/videos/{id}/content` 拼绝对 URL 后再鉴权下载
- **提供商/轮询回归（E11）**：补强「假 completed / 无 url」用例，防回潮
- **`VID-PLAYER` 体验债（E2–E3）**：失败/弱网中文提示+重试；封面占位 / keepFrame / buffering 加载态对齐
- **灯箱来源（E6）**：双端「参考 / 结果」角标
- **空态 / 动效 / 密度（E7–E9）**：提供商空态 CTA；主路径短动效对齐 Motion token；compact/comfortable 与字号极端档主路径不溢出

---

## [1.0.5] — 2026-09-14

### 用户摘要

- 图生图 / 图生视频会记住参考图，气泡里可点开回看
- 视频队列成功项显示封面；播放器支持音量与真全屏
- 桌面改为单实例：再开一次会唤起已有窗口
- 关于页可查看第三方播放相关开源许可

### Added

- **`IMG-TURN-REF` / `VID-TURN-REF`（P4）**：提交图生图/图生视频时将参考图落盘为会话资产（`referenceImages: List<ImageRef>`），双端用户气泡展示缩略并可点开灯箱；旧回合无资产仅显示提示词；删除会话/清数据时一并清理；备份导出省略本地 file 字节
- **DESIGN P4 规格**：`VID-PLAYER` 音量 + 系统级全屏；`VID-QUEUE` 成功项封面缩略；`IMG-TURN-REF` / `VID-TURN-REF`（图生图/图生视频用户气泡回看参考图）；对话气泡附图本期不做
- **`VID-QUEUE` 成功项封面缩略（P2.3）**：双端队列对 `success` 条目显示小封面；来源优先 CDN/`posterUrl` → 本机成片抽帧 JPEG 缓存（`video_poster_cache`）→ 占位；点击封面等同播放；`VideoPosterStore`/`VideoPosterService` 在 core，抽帧由双端注入 `media_kit`；清数据/`SET-DATA` 一并清理封面缓存
- **桌面单实例（`SHELL-SINGLE`）**：`desktop_fluent` 启动早期握手；次进程退出并唤起首实例（含托盘隐藏恢复）；IPC/锁失败降级允许启动并记运行日志
- **`SET-ABOUT` 第三方播放/编解码库许可**：双端关于页「开源许可」入口；列出 `media_kit` 家族、libmpv、FFmpeg 及许可类型与官方主页 URL（可复制）
- **`VID-PLAYER` 音量 + 真全屏（P2.1 / P2.2）**：双端控件条静音切换 + 0–100 音量滑杆（`media_kit` `setVolume`，默认跟随内核 100，不跨启动持久化）；桌面 `window_manager.setFullScreen` 系统级全屏（内嵌/放大弹窗均可进入，Esc / 退出按钮还原；与窗内「放大」并存）；移动 `SystemChrome` 沉浸 + 可横屏，系统返回或退出全屏按钮还原

### Changed

- **Fluent 生视频 OD 精修跟版**：对照 `fluent-*-video.html` — 忙态 CTA「停止任务」；参考图空态虚线/「首帧」文案；队列气泡密度与筛选 chip；abandoned 淡化；空舞台两级文案与播放器头 hint；移动端同步「停止任务」文案（不跟 Fluent 视觉密度）
- **`*-TURN-REF` 气泡布局**：参考图缩略由提示词下方改为 **左侧**（meta 通栏；左缩略 + 右提示词）；对齐 OD 稿；双端生图/生视频用户气泡
- **双端 `VID-PLAYER` 迁 `media_kit`**：`desktop_fluent` 内嵌 / 放大弹窗与 `mobile_material` 推页播放均改用 `media_kit` + `media_kit_video` + `media_kit_libs_video`；移除 `video_player` / `video_player_win` 与 `VideoPlaybackGuard`；桌面弹窗独立 Player（关闭 dispose，打开时内嵌暂停），移动推页 pop 即 dispose
- **CI / 发版钉死 Flutter 3.44.5**：`ci.yml` / `build.yml` / `release.yml` 的 `flutter-action` 增加 `flutter-version: "3.44.5"`，避免 `channel: stable` 漂到 3.47.x

### Fixed

- **桌面 `VID-PLAYER` 切换黑闪**：队列切换任务时保留上一帧（或封面），新源可解码后再挂载，避免先清空成黑底
- **桌面 `VID-PLAYER` 控件条**：进度 / 音量 / 全屏合并为 OD `transport` 单行（内嵌面板与放大弹窗）
- **Windows 安装包内嵌视频黑屏**：`v1.0.4` 由 CI 的 Flutter **3.47.3** 构建，同机本机 **3.44.5** 的 `flutter run` / `build windows --release` 可播；安装目录 exe 仍黑。根因是引擎版本漂移（非业务代码 / 非视频文件）；钉版本后重打 Windows 安装包即可

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

### 用户摘要

- 首个正式版：桌面与手机均可对话、生图、生视频并管理提供商与外观
- 密钥保存在系统凭据库；支持本机备份与直链检查更新
- 安装后显示名为 **AI Studio**；Windows / macOS / Android 按平台分发包

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
