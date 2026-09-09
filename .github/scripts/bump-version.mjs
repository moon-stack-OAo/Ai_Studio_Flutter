#!/usr/bin/env node
/**
 * 将双端应用 pubspec 的 version 写成 `x.y.z+<Unix秒>`（build 可选手动指定）。
 *
 * 用法（仓库根目录）:
 *   node .github/scripts/bump-version.mjs 1.0.2
 *   node .github/scripts/bump-version.mjs v1.0.2
 *   node .github/scripts/bump-version.mjs 1.0.2 --build 1757400000
 *   node .github/scripts/bump-version.mjs 1.0.2 --dry-run
 *
 * 约定：build number 须单调递增；已发 1.0.1+2 起下一版用 Unix 秒。
 * 本脚本只改文件，不 commit / tag / push。
 */
import fs from 'node:fs'
import path from 'node:path'

const PUBSPECS = [
  'apps/desktop_fluent/pubspec.yaml',
  'apps/mobile_material/pubspec.yaml',
]

const VERSION_LINE_RE = /^version:\s*.+$/m
const VERSION_VALUE_RE = /^(\d+\.\d+\.\d+)\+(\d+)$/

function usage(exitCode = 1) {
  console.error(`用法: node .github/scripts/bump-version.mjs <x.y.z|vX.Y.Z> [--build <n>] [--dry-run]
示例: node .github/scripts/bump-version.mjs 1.0.2`)
  process.exit(exitCode)
}

function parseArgs(argv) {
  const args = argv.slice(2)
  let versionArg = ''
  let buildOverride = null
  let dryRun = false

  for (let i = 0; i < args.length; i += 1) {
    const a = args[i]
    if (a === '--dry-run') {
      dryRun = true
      continue
    }
    if (a === '--build') {
      const raw = args[i + 1]
      if (!raw || !/^\d+$/.test(raw)) {
        console.error('--build 需要正整数字面量')
        usage()
      }
      buildOverride = Number(raw)
      i += 1
      continue
    }
    if (a.startsWith('-')) {
      console.error(`未知参数: ${a}`)
      usage()
    }
    if (versionArg) {
      console.error('只能指定一个版本号')
      usage()
    }
    versionArg = a
  }

  if (!versionArg) usage()

  const version = String(versionArg).trim().replace(/^v/i, '')
  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    console.error(`版本号无效: ${versionArg}（期望 x.y.z）`)
    process.exit(1)
  }

  return { version, buildOverride, dryRun }
}

function readVersion(filePath) {
  const text = fs.readFileSync(filePath, 'utf8')
  const m = text.match(VERSION_LINE_RE)
  if (!m) {
    throw new Error(`${filePath}: 未找到 version: 行`)
  }
  const value = m[0].replace(/^version:\s*/, '').trim()
  const parsed = value.match(VERSION_VALUE_RE)
  if (!parsed) {
    throw new Error(`${filePath}: version 格式应为 x.y.z+build，当前为 ${value}`)
  }
  return {
    text,
    line: m[0],
    name: parsed[1],
    build: Number(parsed[2]),
    value,
  }
}

function main() {
  const { version, buildOverride, dryRun } = parseArgs(process.argv)
  const root = process.cwd()

  const currents = PUBSPECS.map((rel) => {
    const abs = path.join(root, rel)
    if (!fs.existsSync(abs)) {
      console.error(`未找到 ${rel}`)
      process.exit(1)
    }
    return { rel, abs, ...readVersion(abs) }
  })

  const maxBuild = Math.max(...currents.map((c) => c.build))
  const build = buildOverride ?? Math.floor(Date.now() / 1000)

  if (!Number.isInteger(build) || build <= 0) {
    console.error(`build number 无效: ${build}`)
    process.exit(1)
  }
  if (build <= maxBuild) {
    console.error(
      `build number ${build} 未大于当前最大 build ${maxBuild}；请稍后重试或传 --build`,
    )
    process.exit(1)
  }

  const nextValue = `${version}+${build}`

  for (const cur of currents) {
    if (!VERSION_LINE_RE.test(cur.text)) {
      console.error(`${cur.rel}: 无法替换 version 行`)
      process.exit(1)
    }
    const nextText = cur.text.replace(VERSION_LINE_RE, `version: ${nextValue}`)
    console.log(`${cur.rel}: ${cur.value} → ${nextValue}`)
    if (!dryRun) {
      fs.writeFileSync(cur.abs, nextText, 'utf8')
    }
  }

  if (dryRun) {
    console.log('（dry-run，未写入文件）')
  } else {
    console.log(`已写入 version: ${nextValue}`)
    console.log('下一步：更新 CHANGELOG → commit → tag v' + version + ' → push')
  }
}

main()
