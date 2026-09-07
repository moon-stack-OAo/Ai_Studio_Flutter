# Changelog

本文件记录 AI Studio（Flutter）仓库的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

版本标题格式：`## [x.y.z] — yyyy-MM-dd`（方括号内为 semver；日期用 ISO；中间为 em dash `—`）。  
发版时由 `.github/scripts/extract-changelog.mjs` 按 tag（如 `v1.0.0`）截取对应章节生成 GitHub Release 正文。

应用版本以 `apps/desktop_fluent` / `apps/mobile_material` 的 `pubspec.yaml` 为准；共享包（`core` / `design_*`）当前为 `0.0.1`，随应用能力一并演进，不单独发版叙事。

---

## [1.0.0] — 2026-09-07

首个可交付基线：双端独立 UI + 共享 `core`，覆盖对话 / 生图 / 生视频 / 设置与更新主路径（对应 `DESIGN.md` P0–P2；P3 抛光含 a11y 全路径自证）。

### 发版摘要

- **双端可用**：Windows / macOS（Fluent）与 Android / iOS（Material 3）能力对等、UI 独立
- **核心能力**：流式对话、文生/图生图、文生/图生视频、多提供商与本机密钥、外观与日志、数据备份
- **直链更新**：桌面 `latest.json`（minisign）· Android `android-latest.json`（sha256 侧载）；更新源指向本仓 Releases
- **安装显示名**：安装后桌面快捷方式 / 开始菜单 / 移动桌面图标统一为 **AI Studio**
- **分发产物**：`AI.Studio_<version>_x64-setup.exe`（Inno）· `AI.Studio_<version>.apk`

### Added

#### 用户可见

- 对话：SSE 流式、停止 / 撤回、Markdown、会话参数覆盖、可搜索模型选择
- 生图：文生 / 图生、时间线、灯箱、另存；移动端相册与系统分享
- 生视频：任务进度、恢复、播放与另存；移动端分享
- 设置五分类：提供商 / 对话默认 / 外观 / 日志 / 关于
- 桌面：托盘、关闭三态（Ask · Quit · Tray）、无边框标题栏、冷启动更新横幅
- 移动：底栏四入口、IME 时隐藏底栏、返回托管（`BackHost`）、冷启动更新横幅
- Android 侧载更新；iOS 非 Store 分发说明

#### 工程与设计系统

- Dart workspace：`apps/desktop_fluent`、`apps/mobile_material`、`packages/core`、`packages/design_fluent`、`packages/design_material`
- Fluent / Material 分栈 token 与 Theme（亮色 Claude 向、暗色 Cursor 向；字号五档；密度 comfortable / compact）
- OpenDesign 双系统原型副本（`design/opendesign/`）与品牌图标源（`design/brand/`）
- 产品规格 `DESIGN.md`、安全说明 `SECURITY.md`、助手约定 `AGENTS.md`
- **CI / 发版**：`.github/workflows`（`ci` / `build` / `release`）、Inno 脚本 `packaging/windows/ai-studio.iss`、清单与签名脚本（`.github/scripts/`）

#### packages/core（业务层）

- **对话**：OpenAI 兼容 SSE、会话持久化、上下文裁剪、`GenerationRuntime`
- **生图 / 生视频**：客户端、会话与资产落盘、pending 恢复、图片压缩
- **提供商**：CRUD、预设、三模型分类、连通性探测、密钥 `flutter_secure_storage`（含旧明文迁移）
- **设置**：外观、对话默认、备份导入导出与清理、存储占用估算
- **更新**：桌面清单 / minisign；Android 侧载清单 / sha256；更新横幅偏好
- **安全 / 日志 / 提示词**：`url_safety`、应用日志、维度构建与 LLM 润色
- 核心单测覆盖 SSE、会话、安全存储、更新验签、备份、URL 安全等

#### 桌面 Fluent（实现要点）

- NavigationView 四入口 + 自绘标题栏；会话列表窗格；关于页检查更新
- P3：空态插画与文案、短动效、scrim 与密度间距；**a11y 全路径**（Semantics/tooltip/焦点/liveRegion；WCAG 2.2 AA 自证）

#### 移动 Material（实现要点）

- NavigationBar 四入口；会话列表页 + 全屏二级；`share_plus` 系统分享
- P3：同桌面语义的空态 / 动效；**a11y 全路径**（触控 ≥48、会话行 Semantics、liveRegion；WCAG 2.2 AA 自证，非第三方认证）

### Changed

- 默认更新清单 URL 指向本仓 `moon-stack-OAo/Ai_Studio_Flutter` Releases
- 安装后显示名统一为 **AI Studio**（Windows 资源信息、macOS `PRODUCT_NAME`、Android `label`、iOS `CFBundleDisplayName`）；exe / `applicationId` / Dart 包名未改

### Security

- API Key 与元数据分离；日志脱敏；备份默认不含密钥
- 更新包失败安全：缺签名 / 验签失败删除临时文件并阻断安装
- 出站 URL 硬拦云元数据与明显 SSRF 靶点（详见 `SECURITY.md`）

### Notes

- 不上架应用商店；Linux 桌面不在首期验收范围
- Release 需配置 Secrets：`TAURI_SIGNING_PRIVATE_KEY`（必填）；可选 `ANDROID_KEY_*`
- `docs/architecture.md` 部分描述可能滞后于实现，以代码与本 Changelog 为准

---

## [Unreleased]

### Added

（暂无）

### Changed

（暂无）
