# Architecture

实现架构说明（占位）。产品规格以根目录 [`DESIGN.md`](../DESIGN.md) 为准。

## 工程落点

```text
apps/desktop_fluent/     # Win + Mac · Fluent UI
apps/mobile_material/    # Android + iOS · Material 3 UI
packages/core/           # 无 UI：协议 / SSE / adapter / 存储 / 密钥接口
packages/design_fluent/
packages/design_material/
```

## 红线

- 只共享业务进 `packages/core`；两套 UI **禁止互相 import Widget**。
- 亮色 Claude 向、暗色 Cursor 向；亮暗 primary hue 不得共用。
- 不上架；更新走直链 / 侧载清单。

## 提供商与密钥（P0-C）

- 模型：`ProviderConfig`（id / name / type / baseUrl / apiKey / chatModel / imageModel / videoModel / enabled / builtin）
- 仓库：`ProviderRepository`（CRUD、选中、`activeChatCredentials`）
- 存储：`SecureProviderStorage` + `SecretStore`
  - 元数据 → `shared_preferences` 键 `core.providers.v1`（**不含** apiKey）
  - 密钥 → `flutter_secure_storage` 键 `core.provider.keys.v1`（`id → apiKey` JSON；不上传）
  - 迁移：首次 load 将旧 prefs 明文密钥写入安全存储并校验后删除明文；失败保留明文并打日志
  - Windows 需 VS「C++ ATL」；详见 `SECURITY.md`
- 连通性：`ProviderConnectionTester`（默认 `OpenAiCompatibleConnectionTester`：GET `/models`，失败回退最小 chat）
- SSE（B）接入：`providerRepository.activeChatCredentials` → `baseUrl` + `apiKey` + `chatModel`
- 三模型选择：`classifyModelId` / `modelOptionsByKind`（可搜索下拉）；UI=`FilterableModelPicker`

## 桌面窗口（Fluent · 方案 B）

- `window_manager`：`TitleBarStyle.hidden` 无系统栏
- `FluentAppTitleBar`：拖拽区 + 自绘 min/max/close（`DragToMoveArea` / `WindowCaptionButton`）
- 关闭行为（托盘 / 询问）属 P1，当前直接 `close`

## 待补

- 模块依赖图、包边界细则
- SSE / 提供商 adapter 约定（B）
- 桌面 / Android 更新清单协议（`latest.json` / `android-latest.json`）说明
