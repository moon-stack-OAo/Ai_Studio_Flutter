# AI Studio (Flutter)

本地多模态 AI 客户端。密钥与会话仅存本机，无自建后端托管。产品规格以 [`DESIGN.md`](./DESIGN.md) 为准。

由现网 Vue / Tauri 客户端按**能力对等、UI 独立**策略重构：桌面走 Fluent，移动走 Material 3。

## 已决

| 项    | 值                                                  |
|------|----------------------------------------------------|
| 平台   | Windows · macOS · Android · iOS                    |
| UI   | **Fluent**（桌面）与 **Material 3**（移动，含 iOS）两套独立设计系统   |
| 色彩   | 亮色仿 Claude · 暗色仿 Cursor（亮暗 primary hue 不得共用）       |
| 字体   | Fluent=Segoe 系；Material=Roboto/Noto；系统字体、不内嵌商业正文字库 |
| 分发   | **不上架**；桌面直链清单 + Android 侧载清单自动更新                  |
| 业务共享 | 仅 `packages/core`；禁止共用 Widget 换皮冒充双系统              |
| 版本   | 应用 `1.0.0+1` · 共享包 `0.0.1`                         |

## 能力概览

| 能力                              | 桌面 Fluent | 移动 Material |
|---------------------------------|-----------|-------------|
| 对话（SSE 流式 / 停止 / 撤回 / Markdown） | ✅         | ✅           |
| 生图（文生 / 图生、时间线、另存）              | ✅         | ✅（含相册）      |
| 生视频（任务进度、恢复、播放、另存）              | ✅         | ✅           |
| 设置五分类（提供商 / 对话 / 外观 / 日志 / 关于）  | ✅         | ✅（五 Tab）    |
| 提供商与密钥（安全存储、连通性、三模型选择）          | ✅         | ✅           |
| 托盘 / 关闭行为（Ask · Quit · Tray）    | ✅         | —           |
| 直链 / 侧载更新（minisign / sha256）    | ✅         | ✅（Android）  |
| 数据备份导入导出与清理                     | ✅         | ✅           |

分期对照见 `DESIGN.md` §9：P0–P2 主路径已落地；P3 抛光与无障碍专项仍可继续。

## 目录

```text
apps/
  desktop_fluent/      # Windows + macOS · Fluent UI
  mobile_material/     # Android + iOS · Material 3 UI
packages/
  core/                # 协议 / SSE / adapter / 存储 / 更新（无 UI）
  design_fluent/       # Fluent token · Theme · 基础确认框
  design_material/     # Material token · Theme · 基础确认框
design/
  brand/               # 应用图标源
  opendesign/          # OpenDesign 原型副本（ai-studio-flutter-proto）
docs/                  # 架构等实现文档
tool/                  # 预留（脚本等，当前为空）
```

根 `pubspec.yaml` 为 Dart workspace，统一管理上述成员包。

## 架构

```text
┌──────────────────────────┬───────────────────────────┐
│  design_fluent +         │  design_material +        │
│  desktop_fluent          │  mobile_material          │
│  Windows · macOS         │  Android · iOS            │
│  独立页面 · 组件 · 导航   │  独立页面 · 组件 · 导航    │
├──────────────────────────┴───────────────────────────┤
│  packages/core                                         │
│  会话 · 生图/生视频 · 提供商 · 安全 URL · 更新 · 备份   │
└────────────────────────────────────────────────────────┘
```

## 开发

前置：已安装 Flutter（SDK 需满足各包 `environment.sdk`，当前为 `^3.12.0`）。

```bash
# 在仓库根拉取依赖（workspace）
flutter pub get

# 桌面（Windows）
cd apps/desktop_fluent && flutter run -d windows

# 桌面（macOS）
cd apps/desktop_fluent && flutter run -d macos

# 移动
cd apps/mobile_material && flutter run

# 测试
dart test packages/core
cd apps/desktop_fluent && flutter test
cd apps/mobile_material && flutter test
```

Windows 使用 `flutter_secure_storage` 时需 VS Build Tools 的 **C++ ATL**（详见 [`SECURITY.md`](./SECURITY.md)）。

## 架构红线

- **只共享业务**：协议 / SSE / adapter / 存储 / 更新进 `packages/core`。
- **两套独立 UI**：`design_fluent` + `desktop_fluent` 与 `design_material` + `mobile_material` **禁止互相 import Widget**。
- 亮暗 primary hue 不得共用；字体栈按设计系统拆分（见 `DESIGN.md` §2.2.2）。
- 不上架；更新走直链 / 侧载清单。
- 未经授权不 `commit` / `push`、不改版本号发版。

## 文档索引

| 文档                                               | 说明                     |
|--------------------------------------------------|------------------------|
| [`DESIGN.md`](./DESIGN.md)                       | 产品规格（双系统、能力表、分期、原型）    |
| [`CHANGELOG.md`](./CHANGELOG.md)                 | 版本变更记录                 |
| [`docs/architecture.md`](./docs/architecture.md) | 工程架构                   |
| [`SECURITY.md`](./SECURITY.md)                   | 安全模型（密钥本机、URL 安全、更新验签） |
| [`AGENTS.md`](./AGENTS.md)                       | 给 AI 编码助手的仓库约定         |

## 原型

OpenDesign 项目 id：`ai-studio-flutter-proto`；仓库权威副本在 `design/opendesign/`（亮/暗 × Fluent/Material，约 27 页 HTML）。

- 禁止 `collect_brief`；用 `skipDiscoveryBrief` + `start_run`。
- 同主题导航联动；外观主题跳对侧稿。
- 同步与冲突流程见 `.opencode/skills/opendesign-proto/SKILL.md`。
