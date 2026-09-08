#!/usr/bin/env node
/**
 * 从 CHANGELOG.md 提取指定版本章节，写入 release-notes.md
 * 用法: node .github/scripts/extract-changelog.mjs v1.0.0
 */
import fs from 'node:fs'
import path from 'node:path'

const tag = process.argv[2] || process.env.GITHUB_REF_NAME || ''
const version = String(tag).trim().replace(/^v/i, '')
if (!version) {
  console.error('缺少版本号，请传入 tag（如 v1.0.0）')
  process.exit(1)
}

const root = process.cwd()
const changelogPath = path.join(root, 'CHANGELOG.md')
const outPath = path.join(root, 'release-notes.md')

if (!fs.existsSync(changelogPath)) {
  console.error('未找到 CHANGELOG.md')
  process.exit(1)
}

const text = fs.readFileSync(changelogPath, 'utf8')
const lines = text.split(/\r?\n/)

const headerRe = new RegExp(`^## \\[v?${version.replace(/\./g, '\\.')}\\](?:\\s|$)`)
const nextHeaderRe = /^## /

let start = -1
for (let i = 0; i < lines.length; i += 1) {
  if (headerRe.test(lines[i])) {
    start = i
    break
  }
}

if (start < 0) {
  console.error(`CHANGELOG.md 中未找到版本 ${version} 的章节（## [${version}]）`)
  process.exit(1)
}

let end = lines.length
for (let i = start + 1; i < lines.length; i += 1) {
  if (nextHeaderRe.test(lines[i])) {
    end = i
    break
  }
}

const sectionLines = lines.slice(start, end)
const body = sectionLines.slice(1).join('\n').replace(/^\s+/, '').replace(/\s+$/, '')

const notes = [
  `## AI Studio v${version}`,
  '',
  body || '_（该版本暂无变更说明）_',
  '',
  '---',
  '',
  '### 下载说明',
  '',
  '请按设备选择下方 Assets 中的安装包：',
  '',
  '| 平台 | 选哪个 | 文件名示例 |',
  '|------|--------|------------|',
  `| Windows x64 | Inno 安装包 | \`AI.Studio_${version}_x64-setup.exe\` |`,
  `| macOS Apple Silicon（M 系列） | zip（内含 .app） | \`AI.Studio_${version}_aarch64.zip\` |`,
  `| macOS Intel | zip（内含 .app） | \`AI.Studio_${version}_x64.zip\` |`,
  `| Android 64 位真机（常见） | APK | \`AI.Studio_${version}_arm64-v8a.apk\` |`,
  `| Android 32 位旧机 | APK | \`AI.Studio_${version}_armeabi-v7a.apk\` |`,
  `| Android x86_64 模拟器 | APK | \`AI.Studio_${version}_x86_64.apk\` |`,
  '',
  '**说明**',
  '',
  '- 不要下 `.sig` / `latest.json` / `android-latest.json` 当安装包（它们供应用内更新校验）。',
  '- macOS 未做 Apple 公证：首次打开若被拦截，请在 Finder 中右键 `.app` →「打开」。',
  '- Android 需允许「安装未知应用」。',
  '',
  '已安装用户可在应用内「设置 → 关于与更新」检查更新（桌面：直链清单；Android：侧载清单）。',
  '',
].join('\n')

fs.writeFileSync(outPath, notes, 'utf8')
console.log(`已写入 ${outPath}（版本 ${version}）`)
