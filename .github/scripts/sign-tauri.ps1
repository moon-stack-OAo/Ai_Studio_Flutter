# 用 @tauri-apps/cli signer 签名安装包（输出与现网 updater 兼容的 .sig）
# 用法:
#   .\sign-tauri.ps1 -File path\to\setup.exe
# 环境变量:
#   TAURI_SIGNING_PRIVATE_KEY
#   TAURI_SIGNING_PRIVATE_KEY_PASSWORD（可空）
param(
  [Parameter(Mandatory = $true)]
  [string]$File
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $File)) {
  throw "文件不存在: $File"
}

if ([string]::IsNullOrWhiteSpace($env:TAURI_SIGNING_PRIVATE_KEY)) {
  throw '缺少环境变量 TAURI_SIGNING_PRIVATE_KEY'
}

# 空密码时显式传空，避免交互提示
if ($null -eq $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD) {
  $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = ''
}

Write-Host "Signing with tauri signer: $File"
npx --yes "@tauri-apps/cli@2" signer sign "$File"
if ($LASTEXITCODE -ne 0) {
  throw "tauri signer sign 失败，exit=$LASTEXITCODE"
}

$sig = "$File.sig"
if (-not (Test-Path -LiteralPath $sig)) {
  throw "未生成签名文件: $sig"
}

Write-Host "已签名: $sig"
