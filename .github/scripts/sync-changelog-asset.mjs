#!/usr/bin/env node
/**
 * 将仓库根 CHANGELOG.md 同步到 packages/core/assets，供关于页运行时读取。
 *
 * 用法（仓库根目录）:
 *   node .github/scripts/sync-changelog-asset.mjs
 *   node .github/scripts/sync-changelog-asset.mjs --dry-run
 *
 * bump-version / 发版前也应跑一遍；改完 CHANGELOG 后请同步再构建。
 */
import fs from 'node:fs'
import path from 'node:path'

const SRC_REL = 'CHANGELOG.md'
const DEST_REL = 'packages/core/assets/CHANGELOG.md'

function main() {
  const dryRun = process.argv.includes('--dry-run')
  const root = process.cwd()
  const src = path.join(root, SRC_REL)
  const dest = path.join(root, DEST_REL)

  if (!fs.existsSync(src)) {
    console.error(`未找到 ${SRC_REL}`)
    process.exit(1)
  }

  const text = fs.readFileSync(src, 'utf8')
  if (!text.trim()) {
    console.error(`${SRC_REL} 为空`)
    process.exit(1)
  }

  console.log(`${SRC_REL} → ${DEST_REL} (${text.length} bytes)`)
  if (dryRun) {
    console.log('（dry-run，未写入）')
    return
  }

  fs.mkdirSync(path.dirname(dest), { recursive: true })
  fs.writeFileSync(dest, text, 'utf8')
  console.log('已同步')
}

main()
