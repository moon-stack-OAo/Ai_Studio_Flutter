#!/usr/bin/env node
/**
 * 生成桌面 latest.json（Tauri 风格，供 Flutter 直链更新）
 * 用法:
 *   node .github/scripts/generate-desktop-latest.mjs v1.0.0 \
 *     --windows-exe packaging/windows/output/AI.Studio_1.0.0_x64-setup.exe \
 *     --windows-sig packaging/windows/output/AI.Studio_1.0.0_x64-setup.exe.sig \
 *     --darwin-arm64 dist/AI.Studio_1.0.0_aarch64.zip \
 *     --darwin-arm64-sig dist/AI.Studio_1.0.0_aarch64.zip.sig \
 *     --darwin-x64 dist/AI.Studio_1.0.0_x64.zip \
 *     --darwin-x64-sig dist/AI.Studio_1.0.0_x64.zip.sig
 *
 * 环境变量: GITHUB_REPOSITORY（默认 moon-stack-OAo/Ai_Studio_Flutter）
 */
import fs from 'node:fs'
import path from 'node:path'

function parseArgs(argv) {
  const out = {
    tag: '',
    windowsExe: '',
    windowsSig: '',
    darwinArm64: '',
    darwinArm64Sig: '',
    darwinX64: '',
    darwinX64Sig: '',
  }
  const rest = [...argv]
  out.tag = String(rest.shift() || process.env.GITHUB_REF_NAME || '').trim()
  while (rest.length) {
    const key = rest.shift()
    const val = String(rest.shift() || '').trim()
    if (key === '--windows-exe' || key === '--exe') out.windowsExe = val
    else if (key === '--windows-sig' || key === '--sig') out.windowsSig = val
    else if (key === '--darwin-arm64') out.darwinArm64 = val
    else if (key === '--darwin-arm64-sig') out.darwinArm64Sig = val
    else if (key === '--darwin-x64') out.darwinX64 = val
    else if (key === '--darwin-x64-sig') out.darwinX64Sig = val
  }
  return out
}

const args = parseArgs(process.argv.slice(2))
const version = args.tag.replace(/^v/i, '')
if (!version) {
  console.error('缺少版本号，请传入 tag（如 v1.0.0）')
  process.exit(1)
}

const repo =
  String(process.env.GITHUB_REPOSITORY || 'moon-stack-OAo/Ai_Studio_Flutter').trim() ||
  'moon-stack-OAo/Ai_Studio_Flutter'
const releaseTag = args.tag.startsWith('v') ? args.tag : `v${version}`

const windowsAsset = `AI.Studio_${version}_x64-setup.exe`
const darwinArm64Asset = `AI.Studio_${version}_aarch64.zip`
const darwinX64Asset = `AI.Studio_${version}_x64.zip`

function firstExisting(paths) {
  for (const p of paths) {
    if (p && fs.existsSync(p)) return p
  }
  return null
}

function resolveBesideSig(filePath, explicit) {
  if (explicit && fs.existsSync(explicit)) return explicit
  if (!filePath) return null
  const beside = `${filePath}.sig`
  if (fs.existsSync(beside)) return beside
  return null
}

function extractNotes() {
  const changelogPath = path.join(process.cwd(), 'CHANGELOG.md')
  if (!fs.existsSync(changelogPath)) return ''
  const lines = fs.readFileSync(changelogPath, 'utf8').split(/\r?\n/)
  const headerRe = new RegExp(`^## \\[v?${version.replace(/\./g, '\\.')}\\](?:\\s|$)`)
  let start = -1
  for (let i = 0; i < lines.length; i += 1) {
    if (headerRe.test(lines[i])) {
      start = i
      break
    }
  }
  if (start < 0) return ''
  let end = lines.length
  for (let i = start + 1; i < lines.length; i += 1) {
    if (/^## /.test(lines[i])) {
      end = i
      break
    }
  }
  return lines
    .slice(start + 1, end)
    .join('\n')
    .replace(/^\s+/, '')
    .replace(/\s+$/, '')
}

function readSignatureBase64(sigPath) {
  const asText = fs.readFileSync(sigPath, 'utf8').trim()
  // tauri signer 写出的 .sig 多为单行 base64；若是 minisign 明文则再包一层
  if (!asText.includes('\n') && /^[A-Za-z0-9+/=\s]+$/.test(asText) && asText.length > 80) {
    return asText.replace(/\s+/g, '')
  }
  return Buffer.from(asText, 'utf8').toString('base64')
}

function requireAsset(label, filePath, assetName) {
  if (!filePath) {
    console.error(`未找到 ${label}（期望 ${assetName}）`)
    process.exit(1)
  }
}

function requireSig(label, sigPath, assetName) {
  if (!sigPath) {
    console.error(`未找到 ${label} 签名（期望 ${assetName}.sig）`)
    process.exit(1)
  }
}

function releaseUrl(assetName) {
  return `https://github.com/${repo}/releases/download/${releaseTag}/${assetName}`
}

function platformEntry(filePath, sigPath, assetName) {
  return {
    url: releaseUrl(assetName),
    signature: readSignatureBase64(sigPath),
  }
}

const windowsExe = firstExisting([
  args.windowsExe,
  path.join(process.cwd(), 'packaging', 'windows', 'output', windowsAsset),
  path.join(process.cwd(), 'dist', windowsAsset),
])
const windowsSig = resolveBesideSig(windowsExe, args.windowsSig)
requireAsset('Windows 安装包', windowsExe, windowsAsset)
requireSig('Windows 安装包', windowsSig, windowsAsset)

const darwinArm64 = firstExisting([
  args.darwinArm64,
  path.join(process.cwd(), 'dist', darwinArm64Asset),
  path.join(process.cwd(), 'packaging', 'macos', 'output', darwinArm64Asset),
])
const darwinArm64Sig = resolveBesideSig(darwinArm64, args.darwinArm64Sig)
requireAsset('macOS Apple Silicon 包', darwinArm64, darwinArm64Asset)
requireSig('macOS Apple Silicon 包', darwinArm64Sig, darwinArm64Asset)

const darwinX64 = firstExisting([
  args.darwinX64,
  path.join(process.cwd(), 'dist', darwinX64Asset),
  path.join(process.cwd(), 'packaging', 'macos', 'output', darwinX64Asset),
])
const darwinX64Sig = resolveBesideSig(darwinX64, args.darwinX64Sig)
requireAsset('macOS Intel 包', darwinX64, darwinX64Asset)
requireSig('macOS Intel 包', darwinX64Sig, darwinX64Asset)

const windowsEntry = platformEntry(windowsExe, windowsSig, windowsAsset)
const arm64Entry = platformEntry(darwinArm64, darwinArm64Sig, darwinArm64Asset)
const x64Entry = platformEntry(darwinX64, darwinX64Sig, darwinX64Asset)

const manifest = {
  version,
  notes: extractNotes(),
  pub_date: new Date().toISOString(),
  product: 'ai-studio-flutter',
  platforms: {
    'windows-x86_64': windowsEntry,
    'windows-x86_64-nsis': windowsEntry,
    'darwin-aarch64': arm64Entry,
    'aarch64-apple-darwin': arm64Entry,
    'darwin-x86_64': x64Entry,
    'x86_64-apple-darwin': x64Entry,
  },
}

const outPath = path.join(process.cwd(), 'latest.json')
fs.writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
console.log(`已写入 ${outPath}`)
console.log(`  version=${version}`)
console.log(`  windows=${windowsExe}`)
console.log(`  darwin-arm64=${darwinArm64}`)
console.log(`  darwin-x64=${darwinX64}`)
