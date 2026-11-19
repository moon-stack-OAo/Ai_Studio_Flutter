import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const scriptsDir = path.dirname(fileURLToPath(import.meta.url))
const version = '9.8.7'
const repo = 'example/update-source-test'
const payload = Buffer.from('release asset fixture')
const signature = Buffer.from('signature fixture').toString('base64')

for (const legacyEnv of [false, true]) {
  for (const platform of ['desktop', 'android']) {
    test(`${platform}: raw GitHub URLs${legacyEnv ? ' despite legacy AppDock env' : ''}`, (t) => {
      const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'ai-studio-manifest-'))
      t.after(() => fs.rmSync(cwd, { recursive: true, force: true }))
      const dist = path.join(cwd, 'dist')
      fs.mkdirSync(dist)
      const names = platform === 'desktop'
        ? [
            `AI.Studio_${version}_x64-setup.exe`,
            `AI.Studio_${version}_aarch64.zip`,
            `AI.Studio_${version}_x64.zip`,
          ]
        : ['arm64-v8a', 'armeabi-v7a', 'x86_64'].map(
            (abi) => `AI.Studio_${version}_${abi}.apk`,
          )
      for (const name of names) {
        fs.writeFileSync(path.join(dist, name), payload)
        if (platform === 'desktop') {
          fs.writeFileSync(path.join(dist, `${name}.sig`), signature)
        }
      }
      const env = { ...process.env, GITHUB_REPOSITORY: repo }
      delete env.APPDOCK_PUBLIC_BASE_URL
      delete env.APPDOCK_APP_SLUG
      if (legacyEnv) {
        env.APPDOCK_PUBLIC_BASE_URL = 'https://legacy.invalid'
        env.APPDOCK_APP_SLUG = 'old-app'
      }
      const result = spawnSync(process.execPath, [
        path.join(scriptsDir, `generate-${platform}-latest.mjs`),
        `v${version}`,
      ], { cwd, env, encoding: 'utf8' })
      assert.equal(result.status, 0, result.stderr || result.stdout)
      const manifest = JSON.parse(fs.readFileSync(
        path.join(cwd, platform === 'desktop' ? 'latest.json' : 'android-latest.json'),
        'utf8',
      ))
      assert.equal(manifest.version, version)
      assert.equal(manifest.product, 'ai-studio-flutter')
      assert.equal(Object.keys(manifest.platforms).length, 6)
      const expectedUrls = names.map(
        (name) => `https://github.com/${repo}/releases/download/v${version}/${name}`,
      )
      assert.deepEqual(
        [...new Set(Object.values(manifest.platforms).map((entry) => entry.url))].sort(),
        expectedUrls.sort(),
      )
      for (const entry of Object.values(manifest.platforms)) {
        if (platform === 'desktop') {
          assert.equal(Buffer.from(entry.signature, 'base64').toString(), signature)
        } else {
          assert.equal(entry.sha256, crypto.createHash('sha256').update(payload).digest('hex'))
          assert.equal(entry.size, payload.length)
        }
      }
    })
  }
}
