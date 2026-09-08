#!/usr/bin/env bash
# 用 @tauri-apps/cli signer 签名安装包（输出与现网 updater 兼容的 .sig）
# 用法: ./sign-tauri.sh path/to/file.zip
# 环境变量:
#   TAURI_SIGNING_PRIVATE_KEY
#   TAURI_SIGNING_PRIVATE_KEY_PASSWORD（可空）
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "文件不存在: ${FILE:-<empty>}" >&2
  exit 1
fi

if [[ -z "${TAURI_SIGNING_PRIVATE_KEY:-}" ]]; then
  echo "缺少环境变量 TAURI_SIGNING_PRIVATE_KEY" >&2
  exit 1
fi

export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:-}"

echo "Signing with tauri signer: $FILE"
npx --yes "@tauri-apps/cli@2" signer sign "$FILE"

SIG="${FILE}.sig"
if [[ ! -f "$SIG" ]]; then
  echo "未生成签名文件: $SIG" >&2
  exit 1
fi

echo "已签名: $SIG"
