# Security

安全与隐私约束。产品层约定见 [`DESIGN.md`](./DESIGN.md) §8。

## 原则

- **本地优先**：配置、密钥、会话、媒体缓存均在本机；无自建后端托管密钥或会话。
- **密钥**：OS 凭据库存储（`flutter_secure_storage` → Windows Credential / Android Keystore / iOS·macOS Keychain）；元数据仍在 `shared_preferences`。
- **日志**：不得含密钥明文（见 `AppLogRepository.sanitizeLogMessage`）。
- **出站 URL**：对齐现网 `urlSafety`（见下节）。

## 出站 URL（urlSafety）

实现：`packages/core/lib/src/security/url_safety.dart`。

- **硬拦**：仅允许 `http` / `https`；拒绝云元数据与明显 SSRF 靶点（`169.254.*`、`metadata.google(.internal)`、`metadata`、`kubernetes.default(.svc)`、`0.0.0.0` / `::` / `::1`、AWS IMDS IPv6 `fd00:ec2::254`、以及 `::ffff:` 映射到链路本地的变体）。
- **放行**：localhost / `127.*` / RFC1918（产品需支持本地与内网中转）。
- **相对路径 / `blob:` / `data:`**：不硬拦。
- **调用点**：保存提供商 `baseUrl`、连通性探测、对话 / 生图 / 生视频请求前、更新清单与安装包下载 URL、媒体下载 URL。
- **warn（不硬拦）**：明文 HTTP、本机、私有网段 → `warnUnsafeUrl`，设置页保存后提示。

## 更新包签名（minisign / Tauri）

实现：`packages/core/lib/src/update/minisign_verify.dart`；桌面 `UpdateClient.downloadInstaller` 在 `requireSignature: true`（默认）时强制校验。

- 公钥钉死为现网 Tauri `plugins.updater.pubkey`（`kDesktopUpdaterMinisignPubkey`）。
- 清单 `platforms.*.signature` 按 Tauri 约定（多为 base64 包一层的 minisign 文本）解析；支持 prehashed（`ED` / BLAKE2b-512）与 legacy（`Ed`）。
- **失败安全**：缺签名、缺公钥、密钥 ID 不匹配、验签失败 → 删除临时文件并阻断安装；**无**默认 skip。
- Android 侧载走 `sha256`（`AndroidUpdateClient` 关闭 minisign）。
- 自动化：`packages/core/test/minisign_verify_test.dart`（自生成测试密钥向量 + `UpdateClient` 失败清理）。
- **手工 E2E（可选）**：用现网私钥 `minisign -S -m <installer>`（或 Tauri bundler 产出的 `.sig`），把签名填入 `latest.json` 的 `platforms.*.signature`，桌面客户端下载后应通过；故意改安装包字节或换签名应阻断并删临时文件。CI 不依赖本机 minisign CLI。

## 密钥存储

| 键 | 介质 | 内容 |
|----|------|------|
| `core.providers.v1` | `shared_preferences` | 提供商元数据 JSON（**不含** apiKey） |
| `core.provider.keys.v1` | `flutter_secure_storage` | `id → apiKey` JSON 映射 |

实现：`SecureProviderStorage` + `SecretStore`（`packages/core`）。

### 迁移（旧明文 → 安全存储）

- 旧版曾把密钥写在同名 prefs 键 `core.provider.keys.v1`。
- **首次 `load`**：若 prefs 仍有该键 → 读出并入安全存储 → 回读校验 → **成功后**再 `prefs.remove`。
- **失败安全**：迁移/校验失败**不**删除明文；打脱敏错误日志；本会话仍可用明文回退。
- 之后每次 `save` 只写安全存储；若仍发现明文残留则在安全写入成功后再清。

### 平台注意

- **Windows**：需 VS Build Tools 的 **C++ ATL**（`atlstr.h`）；运行时用 Credential Manager 存 AES 密钥 + 本地加密文件。
- **Android**：minSdk ≥ 23（本工程默认 24）；`allowBackup="false"` 降低云备份导致密钥解包失败风险；v10+ 默认 RSA-OAEP + AES-GCM（`encryptedSharedPreferences` 已弃用）。
- **iOS / macOS**：Keychain；macOS Runner 需 `keychain-access-groups` entitlement。

禁止：把完整 Key 写入日志、`toString`、崩溃上报或剪贴板默认文案。

## 导入导出与清数据（SET-DATA）

实现：`DataBackupService`（`packages/core`）。

### 导出含 Key 的风险

- 默认 `includeSecrets: false`，备份仅含提供商元数据（id / name / baseUrl / models 等）。
- 若用户显式选择导出密钥（`includeSecrets: true`）：
  - 备份文件等同于**明文密钥副本**；落盘、分享、云同步、截图均可能导致泄露。
  - UI 必须明确警示，并建议加密存储或用完即删。
  - 日志与 Toast **不得**回显 Key 或整份含密钥 JSON。

### 导入恶意 / 过大 JSON

- 仅接受 `schemaVersion == 1`；不兼容版本抛 `DataBackupSchemaException`。
- 非法 JSON / 非对象根节点抛 `DataBackupFormatException`（可读中文信息，避免未捕获崩溃）。
- 有字符上限（约 32MB）；超限拒绝解析，防止 OOM。
- 合并策略：同 id 覆盖非密钥字段；密钥仅在「备份含密钥 **且** `importSecrets: true`」时覆盖。
- 媒体二进制不进 JSON；导入会话后本地 file 路径可能失效，属预期。

### 清数据不可逆

- `clearLocalData` 可清：会话、媒体缓存、外观/对话默认、提供商、日志、密钥。
- **不可逆**；UI 层必须二次确认（`FB-CONFIRM`），并区分「仅会话」「仅缓存」「全部（含密钥）」文案。
- 若有进行中生成任务，UI 应先停止再清；服务层幂等，但不取消网络请求。

### 日志不得含密钥

- 运行日志、错误文案、导出预览、调试打印均须脱敏。
- 清日志（`AppLogRepository.clear`）不恢复密钥；清密钥与清日志独立。

## 待补

- Redirect 目标二次校验（当前仅校验初始请求 URL，与现网一致）
