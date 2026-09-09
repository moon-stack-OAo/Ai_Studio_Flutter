# AI Studio

本地多模态 AI 客户端（Flutter；密钥 / 会话仅存本机，无自建后端）。**能力对等、UI 独立**：桌面 Fluent · 移动 Material 3。

产品规格以 [`DESIGN.md`](./DESIGN.md) 为准；变更见 [`CHANGELOG.md`](./CHANGELOG.md)。

## 已决要点

| 项  | 值                                                 |
|----|---------------------------------------------------|
| 平台 | Windows · macOS · Android · iOS（Linux 不在首期）       |
| UI | **Fluent**（桌面）与 **Material 3**（移动，含 iOS）两套独立设计系统  |
| 分发 | **不上架**；桌面直链清单 + Android 侧载清单；安装显示名 **AI Studio** |

## 仓库结构

```text
apps/
  desktop_fluent/       # Windows + macOS · Fluent UI
  mobile_material/      # Android + iOS · Material 3 UI
packages/
  core/                 # 协议 / SSE / adapter / 存储 / 更新（无 UI）
  design_fluent/        # Fluent token · Theme · 基础确认框
  design_material/      # Material token · Theme · 基础确认框
design/
  brand/                # 应用图标源
  opendesign/           # OpenDesign 原型权威副本（约 27 页 HTML）
docs/                   # 实现文档（architecture 可能滞后于代码）
packaging/
  windows/              # Inno Setup（ai-studio.iss）
.github/
  workflows/            # ci / build / release
  scripts/              # 清单生成、changelog 截取、签名辅助
tool/                   # 预留（当前为空）
```

根 `pubspec.yaml` 为 Dart workspace，统一管理上述成员包。

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

## 能力速查

| 能力                             | 桌面 Fluent | 移动 Material |
|--------------------------------|-----------|-------------|
| 对话（SSE / 停止 / 撤回 / Markdown）   | ✅         | ✅           |
| 生图（文生 / 图生、时间线、另存）             | ✅         | ✅（含相册 / 分享） |
| 生视频（进度、恢复、播放、另存）               | ✅         | ✅（含分享）      |
| 设置五分类（提供商 / 对话 / 外观 / 日志 / 关于） | ✅         | ✅（五 Tab）    |
| 提供商与密钥（安全存储、连通性、三模型可搜索）        | ✅         | ✅           |
| 托盘 / 关闭（Ask · Quit · Tray）     | ✅         | —           |
| 直链 / 侧载更新（minisign / sha256）   | ✅         | ✅（Android）  |
| 数据备份导入导出与清理                    | ✅         | ✅           |
| P3 抛光（空态 / 动效 / 密度 / a11y 自证）  | ✅         | ✅           |

分期与验收细节见 `DESIGN.md` §9（a11y 为全路径自证清单，非第三方 WCAG 认证）。

## 开发

前置：已安装 Flutter（成员包 `environment.sdk` 为 `^3.12.2`；workspace 根为 `^3.12.0`）。

```bash
# 仓库根拉取依赖（workspace）
flutter pub get

# 桌面
cd apps/desktop_fluent && flutter run -d windows
cd apps/desktop_fluent && flutter run -d macos

# 移动
cd apps/mobile_material && flutter run

# 测试（Flutter 包请用 flutter test）
cd packages/core && flutter test
cd packages/design_fluent && flutter test
cd packages/design_material && flutter test
cd apps/desktop_fluent && flutter test
cd apps/mobile_material && flutter test
```

Windows 使用 `flutter_secure_storage` 时需 VS Build Tools 的 **C++ ATL**（见 [`SECURITY.md`](./SECURITY.md)）。

## 架构红线

- **只共享业务**：协议 / SSE / adapter / 存储 / 更新进 `packages/core`。
- **两套独立 UI**：`design_fluent` + `desktop_fluent` 与 `design_material` + `mobile_material` **禁止互相 import Widget**。
- 亮暗 primary hue 不得共用；字体栈按设计系统拆分（`DESIGN.md` §2.2.2）。
- 不上架；更新走直链 / 侧载清单（默认指向本仓 `moon-stack-OAo/Ai_Studio_Flutter` Releases）。
- 未经授权不 `commit` / `push`、不改版本号发版。

## CI / 发版

| Workflow                        | 触发                     | 作用                                                                             |
|---------------------------------|------------------------|--------------------------------------------------------------------------------|
| `.github/workflows/ci.yml`      | PR / push 主分支          | `dart analyze` + 各包 / 应用测试                                                     |
| `.github/workflows/build.yml`   | 手动 `workflow_dispatch` | Windows Inno + macOS zip（aarch64/x64）+ Android APK + iOS 未签名 IPA（artifact，预览用） |
| `.github/workflows/release.yml` | 推送 `v*` tag            | 独立构建 → draft Release → Win/macOS/Android 产物 + 清单 → 正式发布                        |

发版前配置 Secrets：`TAURI_SIGNING_PRIVATE_KEY`（必填）、`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`；可选 `ANDROID_KEY_*`。清单与签名脚本在 `.github/scripts/`。

本地升版（双端 `pubspec` → `x.y.z+Unix秒`，不自动 commit）：

```bash
node .github/scripts/bump-version.mjs 1.0.2
# node .github/scripts/bump-version.mjs 1.0.2 --dry-run
```

## 文档索引

| 文档                                               | 说明                               |
|--------------------------------------------------|----------------------------------|
| [`DESIGN.md`](./DESIGN.md)                       | 产品规格（双系统、能力表、分期、原型）              |
| [`CHANGELOG.md`](./CHANGELOG.md)                 | 版本变更（发版正文由此截取）                   |
| [`LICENSE`](./LICENSE)                           | MIT                              |
| [`docs/architecture.md`](./docs/architecture.md) | 工程架构（部分描述可能滞后，以代码与 Changelog 为准） |
| [`SECURITY.md`](./SECURITY.md)                   | 安全模型（密钥本机、URL 安全、更新验签）           |
| [`AGENTS.md`](./AGENTS.md)                       | AI 编码助手仓库约定                      |

## 原型

OpenDesign 项目 id：`ai-studio-flutter-proto`；**仓库权威副本**在 `design/opendesign/`（亮/暗 × Fluent/Material）。

- 禁止 `collect_brief`；用 `skipDiscoveryBrief` + `start_run`。
- 同主题导航联动；外观主题跳对侧稿。
- 同步与冲突约定见 [`AGENTS.md`](./AGENTS.md)（OpenDesign 原型节）。
