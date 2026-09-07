#!/usr/bin/env node
/**
 * 生成桌面 latest.json（Tauri 风格，供 Flutter 直链更新）
 * 用法:
 *   node .github/scripts/generate-desktop-latest.mjs v1.0.0 \
 *     --exe packaging/windows/output/AI.Studio_1.0.0_x64-setup.exe \
 *     --sig packaging/windows/output/AI.Studio_1.0.0_x64-setup.exe.sig
 *
 * 环境变量: GITHUB_REPOSITORY（默认 moon-stack-OAo/Ai_Studio_Flutter）
 */
import fs from 'node:fs'
import path from 'node:path'

function parseArgs(argv) {
  const out = { tag: '', exe: '', sig: '' }
  const rest = [...argv]
  out.tag = String(rest.shift() || process.env.GITHUB_REF_NAME || '').trim()
  while (rest.length) {
    const key = rest.shift()
    if (key === '--exe') out.exe = String(rest.shift() || '').trim()
    else if (key === '--sig') out.sig = String(rest.shift() || '').trim()
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
const assetName = `AI.Studio_${version}_x64-setup.exe`

function resolveExe() {
  if (args.exe && fs.existsSync(args.exe)) return args.exe
  const candidates = [
    path.join(process.cwd(), 'packaging', 'windows', 'output', assetName),
    path.join(process.cwd(), 'dist', assetName),
  ]
  for (const p of candidates) {
    if (fs.existsSync(p)) return p
  }
  return null
}

function resolveSig(exePath) {
  if (args.sig && fs.existsSync(args.sig)) return args.sig
  const beside = `${exePath}.sig`
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

const exePath = resolveExe()
if (!exePath) {
  console.error(`未找到安装包 ${assetName}`)
  process.exit(1)
}

const sigPath = resolveSig(exePath)
if (!sigPath) {
  console.error(`未找到签名文件（期望 ${assetName}.sig）`)
  process.exit(1)
}

const signature = readSignatureBase64(sigPath)
const url = `https://github.com/${repo}/releases/download/${releaseTag}/${assetName}`
const platformEntry = { url, signature }

const manifest = {
  version,
  notes: extractNotes(),
  pub_date: new Date().toISOString(),
  product: 'ai-studio-flutter',
  platforms: {
    'windows-x86_64': platformEntry,
    'windows-x86_64-nsis': platformEntry,
  },
}

const outPath = path.join(process.cwd(), 'latest.json')
fs.writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
console.log(`已写入 ${outPath}`)
console.log(`  version=${version}`)
console.log(`  exe=${exePath}`)
console.log(`  sig=${sigPath}`)
console.log(`  url=${url}`)
