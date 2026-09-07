# AGENTS.md — Ai_Studio_Flutter

给在本仓库工作的 AI 编码助手的约定。产品规格以 [`DESIGN.md`](./DESIGN.md) 为准。

## 语言

- 与用户对话默认**简体中文**；代码标识符保持英文。
- 未经明确要求不要主动写大段说明文档。

## 架构红线

- **只共享业务**：协议 / SSE / adapter / 存储进 `packages/core`。
- **两套独立 UI**：`design_fluent` + `apps/desktop_fluent` 与 `design_material` + `apps/mobile_material` **禁止互相 import Widget**。
- 亮色 Claude 向、暗色 Cursor 向；亮暗 primary hue 不得共用。
- 字体：Fluent=Segoe 系系统栈；Material=Roboto/Noto 系；**不内嵌**商业正文字库（见 `DESIGN.md` §2.2.2）。
- 不上架；更新走直链/侧载清单。
- 未经授权禁止 `git commit` / `push` / 改版本号发版。
- **不要**把本仓规格回写到 `D:\Moon\tools\AI_Studio\DESIGN.md`。

## OpenDesign 原型

- **权威源**：仓库 `design/opendesign/`；本机 OD 项目 `ai-studio-flutter-proto` 仅为预览/编辑副本。
- 本机路径：`D:\Moon\OD\data\namespaces\release-stable-win\data\projects\ai-studio-flutter-proto`。
- 在 OD 改完须拷回仓库；推 OD 前先 diff，**禁止未确认整目录覆盖**。
- **禁止** `collect_brief`；用 `skipDiscoveryBrief` + `start_run`。
- 同主题导航联动；外观主题跳对侧稿；细滚动条无上下箭头。
- 完整同步/冲突流程见 skill：`.opencode/skills/opendesign-proto/SKILL.md`。

## 常用命令

```bash
flutter pub get
cd apps/desktop_fluent && flutter run -d windows
cd apps/mobile_material && flutter run
dart test path/to/test
```
