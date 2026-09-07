# Changelog

本文件记录 AI Studio（Flutter）仓库的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

应用版本以 `apps/desktop_fluent` / `apps/mobile_material` 的 `pubspec.yaml` 为准；共享包（`core` / `design_*`）当前为 `0.0.1`，随应用能力一并演进，不单独发版叙事。

---

## [1.0.0] — 2026-09-07

首个可交付基线：双端独立 UI + 共享 `core`，覆盖对话 / 生图 / 生视频 / 设置与更新主路径（对应 `DESIGN.md` P0–P2）。

### Added

#### 工程与设计系统

- Dart workspace：`apps/desktop_fluent`、`apps/mobile_material`、`packages/core`、`packages/design_fluent`、`packages/design_material`
- Fluent / Material 分栈 token 与 Theme（亮色 Claude 向、暗色 Cursor 向；字号五档；密度 comfortable / compact）
- OpenDesign 双系统原型副本（`design/opendesign/`，约 27 页）与品牌图标源（`design/brand/`）
- 产品规格 `DESIGN.md`、安全说明 `SECURITY.md`、助手约定 `AGENTS.md`

#### packages/core（业务层）

- **对话**：OpenAI 兼容 SSE 流式客户端、会话本地持久化、停止 / 撤回、上下文裁剪、`GenerationRuntime`
- **生图**：文生图 / 图生图客户端、会话与资产落盘、质量选项、图片压缩
- **生视频**：文生 / 图生客户端（轮询）、会话与资产、pending 任务恢复
- **提供商**：CRUD、预设、chat / image / video 三模型分类与可搜索选项、连通性探测、密钥 `flutter_secure_storage`（含旧明文迁移）
- **设置**：外观、对话默认、数据备份导入导出与本地清理、存储占用估算
- **更新**：桌面清单客户端、版本比较、SHA256、minisign 验签、安装器抽象；Android 侧载清单客户端
- **安全**：出站 URL 校验（`url_safety`）
- **日志**：级别 / 条目 / 仓库与本地存储
- **提示词**：维度构建器、预设、LLM 润色（图 / 视频）
- 核心单测约 27 个（SSE、会话、提供商安全存储、更新验签、备份、URL 安全等）

#### 桌面 Fluent（Windows · macOS）

- NavigationView 四入口壳 + 无边框自绘标题栏（拖拽 / 最小化 / 最大化 / 关闭）
- 对话：会话列表窗格、流式、Markdown、可搜索模型选择、会话覆盖参数
- 生图：参数 / composer、时间线、灯箱、另存为、提示词辅助与构建
- 生视频：队列、播放、pending 恢复、另存为
- 设置五分类：提供商、对话默认、外观、日志、关于（含关闭行为）
- 系统托盘菜单（显示 / 设置 / 检查更新 / 退出）；关闭三态 Ask · Quit · Tray
- 直链自动更新：检查 / 下载 / minisign 验签 / 安装（关于页）

#### 移动 Material（Android · iOS）

- 底部 NavigationBar 四入口壳（IME 可见时隐藏底栏）
- 对话：会话列表页 + 聊天页、流式、Markdown、模型 / 覆盖参数 sheet
- 生图 / 生视频：与桌面对等的主流程 UI；系统相册写入（`gal`）
- 设置五 Tab：提供商 / 对话 / 外观 / 日志 / 关于
- Android 侧载更新（清单 + sha256 + APK 安装）；iOS 非 Store 分发说明文案

### Security

- API Key 与元数据分离存储；日志脱敏；备份默认不含密钥
- 更新包失败安全：缺签名 / 验签失败删除临时文件并阻断安装
- 出站 URL 硬拦云元数据与明显 SSRF 靶点（详见 `SECURITY.md`）

### Notes

- 不上架应用商店；Linux 桌面不在首期验收范围
- `tool/` 目录预留，暂无脚本；`docs/architecture.md` 部分描述可能滞后于实现，以代码与本 Changelog 为准
- P3（动效 / 无障碍专项等）未作为本版本验收范围

---

## [Unreleased]

### Planned (P3)

- Material `SYS-SHARE`：图 / 视频系统分享入口
- 动效 / 空态 / 无障碍专项抛光

---
