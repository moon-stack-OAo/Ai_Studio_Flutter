# AGENTS.md — Ai_Studio_Flutter

给在本仓库工作的 AI 编码助手的约定。产品规格以 [`DESIGN.md`](./DESIGN.md) 为准；显著变更见 [`CHANGELOG.md`](./CHANGELOG.md)。

## 语言

- 与用户对话默认**简体中文**；代码标识符保持英文。
- 未经明确要求不要主动写大段说明文档。

## 架构红线

- **只共享业务**：协议 / SSE / adapter / 存储 / 更新进 `packages/core`。
- **两套独立 UI**：`design_fluent` + `apps/desktop_fluent` 与 `design_material` + `apps/mobile_material` **禁止互相 import Widget**。
- 亮色 Claude 向、暗色 Cursor 向；亮暗 primary hue 不得共用。
- 字体：Fluent=Segoe 系系统栈；Material=Roboto/Noto 系；**不内嵌**商业正文字库（见 `DESIGN.md` §2.2.2）。
- 不上架；更新走直链 / 侧载清单。
- 未经授权禁止 `git commit` / `push` / 改版本号发版。

## 包边界

| 包 / 应用                     | 可放                                                              | 不可放                                                 |
|----------------------------|-----------------------------------------------------------------|-----------------------------------------------------|
| `packages/core`            | 协议、SSE、adapter、提供商、会话/生图/生视频状态、安全存储、URL 安全、更新客户端、备份、日志、无 UI 纯逻辑 | Flutter Widget、主题 token、任一设计系统控件                    |
| `packages/design_fluent`   | Fluent token、Theme、该系统基础确认框等共享壳件                                | 业务 API 调用、会话持久化、Material / 移动专用 Widget              |
| `packages/design_material` | Material token、Theme、该系统基础确认框等共享壳件                              | 业务 API 调用、会话持久化、Fluent / 桌面专用 Widget                |
| `apps/desktop_fluent`      | Windows/macOS 页面、导航、托盘、窗口、桌面平台插件接线                              | `import` Material 侧 Widget；把可复用业务逻辑堆在 app 而不下沉 core |
| `apps/mobile_material`     | Android/iOS 页面、底栏、相册/分享、返回托管等                                   | `import` Fluent 侧 Widget；把可复用业务逻辑堆在 app 而不下沉 core   |

能力对等 ≠ 布局/组件同构。改一端 UI 时，另一端按**同一能力**各自实现，不要抽「通用 Widget 换皮」。

## 改代码约定

- **规格优先**：行为以 `DESIGN.md` 为准；实现与文档冲突时先对齐规格或请用户确认后再改。
- **双端能力**：触及对话 / 生图 / 生视频 / 设置 / 更新等共享能力时，评估桌面与移动是否都要改；仅一端需要时说明原因。
- **下沉判断**：两端都会用的逻辑进 `core`；仅一端的 UI/平台代码留在对应 `apps/*` 或 `design_*`。
- **风格**：跟随邻近文件既有写法；不擅自引入未在 workspace 使用的依赖；不主动写大段文档（除非用户要求）。
- **测试**：改 `packages/core` / `design_*` 尽量补/跑 `flutter test`（Flutter 包不能用 `dart test`）；改 UI 行为时在对应 app 跑 `flutter test`（或说明无法跑的原因）。
- **安全**：不把密钥写入日志、备份默认或仓库文件；出站 URL 走 `url_safety`；更新验签失败必须阻断（见 `SECURITY.md`）。
- **文档同步**：用户可见能力或分期状态变化时，按需更新 `CHANGELOG.md` / `DESIGN.md`；`docs/architecture.md` 可能滞后，勿把它当唯一真相。

## Git / 发版边界

- **禁止**（除非用户明确授权）：`git add` / `commit` / `push` / `reset` / `rebase`、强推、改版本号、打 tag、改 Release Secrets。
- 应用版本以 `apps/desktop_fluent` 与 `apps/mobile_material` 的 `pubspec.yaml` 为准（当前 `1.0.0+1`）；共享包 `0.0.1` 不单独发版叙事。
- 发版入口：推送 `v*` tag → `.github/workflows/release.yml`（draft → 双端产物 + `latest.json` / `android-latest.json`）。
- Secrets：`TAURI_SIGNING_PRIVATE_KEY`（必填）、`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`；可选 `ANDROID_KEY_*`。助手不创建、不回显、不提交私钥。
- 产物命名：`AI.Studio_<ver>_x64-setup.exe` · `AI.Studio_<ver>.apk`；默认更新源指向本仓 Releases。
- 未 push 前的多次本地修改视为同一版本演进；未明确要求 TAG 前不随意改版本号。

## OpenDesign 原型

| 位置                                 | 角色                            |
|------------------------------------|-------------------------------|
| 仓库 `design/opendesign/`            | **权威源**（对照 `DESIGN.md` 与实现验收） |
| 本机 OD 项目 `ai-studio-flutter-proto` | **工作副本**（应用内预览 / 编辑）          |

本机路径（当前环境）：

```text
D:\Moon\OD\data\namespaces\release-stable-win\data\projects\ai-studio-flutter-proto
```

### 红线

- **禁止** `collect_brief`；用 `skipDiscoveryBrief` + `start_run`。
- 同主题主导航互跳；外观「浅色 / 深色」跳对侧主题稿（无跟随系统）。
- 细滚动条（约 6px）、无上下箭头。
- Fluent / Material **分栈字体**；系统字体，无商业字库内嵌。
- 未确认前**不要**整目录强制覆盖（任一侧都可能有未同步改动）。
- 不要默认同步 `*.artifact.json`（OD 内部产物），除非用户明确要求。

### 工作流

**A. 在 OD 应用里改原型**

1. 打开 `ai-studio-flutter-proto` 编辑。
2. 改完后**立刻**将变更拷回仓库 `design/opendesign/`（同名 HTML / 资源）。
3. 需要时再改 `DESIGN.md`，使规格与原型一致。

**B. 在仓库里改原型**

1. 编辑 `design/opendesign/*.html`（及 `assets/`）。
2. **先 diff** 再推送到本机 OD 项目对应文件。
3. 请用户在 OD 中重新打开 / 刷新该稿（注意缓存）。

**C. 同步前必做：对比确认**

对两边 HTML 做文件名集合 + hash / 时间对比，向用户报告：

1. 仅仓库有 / 仅 OD 有
2. 仓库较新（可推 OD）
3. OD 较新（应先拉回仓库，或确认后放弃 OD 侧）
4. 与当前任务相关的内容差（关键标记、文案、能力 id）

**默认请用户确认范围后再拷贝**，不要静默整目录覆盖。

**D. 冲突处理**

- 有明确产品决策且已写入仓库 / `DESIGN.md` → **以仓库为准**覆盖 OD 对应文件。
- 仅 OD 内视觉微调、仓库较旧 → **先 OD → 仓库**，再继续改。
- 两侧都改同一文件 → 展示 diff 要点，请用户选权威侧或手工合并。

### 助手输出习惯

- 同步前：给对比摘要 + 拟拷贝列表，等确认。
- 同步后：列出已拷路径、校验（hash 或关键字符串）、提醒刷新 OD。
- 实现代码前：若用户要求「先改 OD」，只动原型 / `DESIGN.md`，不改 Flutter，直到用户确认。

## 常用命令

```bash
flutter pub get
cd apps/desktop_fluent && flutter run -d windows
cd apps/desktop_fluent && flutter run -d macos
cd apps/mobile_material && flutter run
cd packages/core && flutter test
cd packages/design_fluent && flutter test
cd packages/design_material && flutter test
cd apps/desktop_fluent && flutter test
cd apps/mobile_material && flutter test
```
