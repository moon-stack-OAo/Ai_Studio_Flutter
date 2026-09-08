#!/usr/bin/env node
/**
 * 生成 android-latest.json（Android 侧载应用内更新，按 ABI 分包）
 * 用法:
 *   node .github/scripts/generate-android-latest.mjs v1.0.0 [distDir]
 *   node .github/scripts/generate-android-latest.mjs v1.0.0 apk1.apk apk2.apk ...
 * 环境变量可选: GITHUB_REPOSITORY（默认 moon-stack-OAo/Ai_Studio_Flutter）
 */
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const tag = String(process.argv[2] || process.env.GITHUB_REF_NAME || '').trim()
const version = tag.replace(/^v/i, '')
if (!version) {
  console.error('缺少版本号，请传入 tag（如 v1.0.0）')
  process.exit(1)
}

const repo =
  String(process.env.GITHUB_REPOSITORY || 'moon-stack-OAo/Ai_Studio_Flutter').trim() ||
  'moon-stack-OAo/Ai_Studio_Flutter'
const releaseTag = tag.startsWith('v') ? tag : `v${version}`
const extraArgs = process.argv.slice(3)

/** @type {{ abi: string, suffixes: string[], platformKeys: string[] }[]} */
const ABI_SPECS = [
  {
    abi: 'arm64-v8a',
    suffixes: ['arm64-v8a', 'arm64'],
    platformKeys: ['aarch64-linux-android', 'arm64-v8a'],
  },
  {
    abi: 'armeabi-v7a',
    suffixes: ['armeabi-v7a', 'armeabi', 'armv7'],
    platformKeys: ['armeabi-v7a', 'armv7-linux-androideabi'],
  },
  {
    abi: 'x86_64',
    suffixes: ['x86_64', 'x86-64'],
    platformKeys: ['x86_64', 'x86_64-linux-android'],
  },
]

function assetNameForAbi(abi) {
  return `AI.Studio_${version}_${abi}.apk`
}

function detectAbi(filePath) {
  const name = path.basename(filePath).toLowerCase()
  for (const spec of ABI_SPECS) {
    for (const suffix of spec.suffixes) {
      if (name.includes(suffix.toLowerCase())) return spec.abi
    }
  }
  return null
}

function collectCandidateFiles() {
  /** @type {string[]} */
  const files = []
  if (!extraArgs.length) {
    const defaults = [
      path.join(process.cwd(), 'dist'),
      path.join(
        process.cwd(),
        'apps',
        'mobile_material',
        'build',
        'app',
        'outputs',
        'flutter-apk',
      ),
    ]
    for (const dir of defaults) {
      if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) continue
      for (const name of fs.readdirSync(dir)) {
        if (name.toLowerCase().endsWith('.apk')) {
          files.push(path.join(dir, name))
        }
      }
    }
    return files
  }

  for (const arg of extraArgs) {
    if (!fs.existsSync(arg)) continue
    const st = fs.statSync(arg)
    if (st.isDirectory()) {
      for (const name of fs.readdirSync(arg)) {
        if (name.toLowerCase().endsWith('.apk')) {
          files.push(path.join(arg, name))
        }
      }
    } else if (st.isFile() && arg.toLowerCase().endsWith('.apk')) {
      files.push(arg)
    }
  }
  return files
}

function preferApk(a, b, abi) {
  const an = path.basename(a).toLowerCase()
  const bn = path.basename(b).toLowerCase()
  const expected = assetNameForAbi(abi).toLowerCase()
  const aExact = an === expected ? 1 : 0
  const bExact = bn === expected ? 1 : 0
  if (aExact !== bExact) return bExact - aExact
  const aRelease = an.includes('release') ? 1 : 0
  const bRelease = bn.includes('release') ? 1 : 0
  if (aRelease !== bRelease) return bRelease - aRelease
  const aUnsigned = an.includes('unsigned') ? 1 : 0
  const bUnsigned = bn.includes('unsigned') ? 1 : 0
  return aUnsigned - bUnsigned
}

function resolveAbiApks() {
  const files = collectCandidateFiles()
  /** @type {Map<string, string>} */
  const byAbi = new Map()

  for (const spec of ABI_SPECS) {
    const expected = path.join(process.cwd(), 'dist', assetNameForAbi(spec.abi))
    if (fs.existsSync(expected)) {
      byAbi.set(spec.abi, expected)
      continue
    }
    const matched = files.filter((f) => detectAbi(f) === spec.abi)
    if (!matched.length) continue
    matched.sort((a, b) => preferApk(a, b, spec.abi))
    byAbi.set(spec.abi, matched[0])
  }

  return byAbi
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

const byAbi = resolveAbiApks()
if (!byAbi.size) {
  console.error(
    `未找到按 ABI 拆分的 APK（期望如 ${assetNameForAbi('arm64-v8a')}）`,
  )
  process.exit(1)
}

const required = ABI_SPECS.map((s) => s.abi)
const missing = required.filter((abi) => !byAbi.has(abi))
if (missing.length) {
  console.error(`缺少 ABI 分包: ${missing.join(', ')}`)
  for (const [abi, file] of byAbi.entries()) {
    console.error(`  已找到 ${abi}: ${file}`)
  }
  process.exit(1)
}

/** @type {Record<string, { url: string, sha256: string, size: number }>} */
const platforms = {}

for (const spec of ABI_SPECS) {
  const apkPath = byAbi.get(spec.abi)
  const buf = fs.readFileSync(apkPath)
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex')
  const size = buf.length
  const name = assetNameForAbi(spec.abi)
  const url = `https://github.com/${repo}/releases/download/${releaseTag}/${name}`
  const entry = { url, sha256, size }
  for (const key of spec.platformKeys) {
    platforms[key] = entry
  }
  console.log(`  ${spec.abi}: ${apkPath}`)
  console.log(`    asset=${name}`)
  console.log(`    sha256=${sha256}`)
  console.log(`    size=${size}`)
}

const manifest = {
  version,
  notes: extractNotes(),
  pub_date: new Date().toISOString(),
  product: 'ai-studio-flutter',
  platforms,
}

const outPath = path.join(process.cwd(), 'android-latest.json')
fs.writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
console.log(`已写入 ${outPath}`)
console.log(`  version=${version}`)
console.log(`  abis=${[...byAbi.keys()].join(',')}`)
