// Dependency-free regression guardrails, not a YAML/actionlint replacement.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

const workflow = fs.readFileSync(new URL('../workflows/native-compile.yml', import.meta.url), 'utf8')

test('native CI covers all four production entrypoints without release packaging', () => {
  assert.match(workflow, /working-directory: apps\/desktop_fluent\s+run: flutter --no-version-check build windows --debug --no-pub/)
  assert.match(workflow, /working-directory: apps\/desktop_fluent\s+run: flutter --no-version-check build macos --debug --no-pub/)
  assert.match(workflow, /working-directory: apps\/mobile_material\s+run: flutter --no-version-check build apk --debug --target-platform android-arm64 --no-pub/)
  assert.match(workflow, /working-directory: apps\/mobile_material\s+run: flutter --no-version-check build ios --simulator --debug --no-codesign --no-pub/)
  assert.equal((workflow.match(/flutter-version: '3\.44\.5'/g) || []).length, 3)
  assert.equal((workflow.match(/pub get --enforce-lockfile/g) || []).length, 3)
  assert.equal((workflow.match(/timeout-minutes: \d+/g) || []).length, 3)
})

test('fork PR builds remain read-only and do not publish or launch apps', () => {
  assert.match(workflow, /permissions:\s+contents: read/)
  assert.equal((workflow.match(/persist-credentials: false/g) || []).length, 3)
  assert.doesNotMatch(workflow, /pull_request_target|secrets\s*[.\[]|contents: write|upload-artifact|--release|flutter run|flutter drive/)
  assert.match(workflow, /cancel-in-progress: true/)
})

test('PR and branch pushes cover shared assets, plugins, lockfiles and CI itself', () => {
  assert.match(workflow, /branches: \[main, master, dev\]/)
  assert.match(workflow, /workflow_dispatch:/)
  for (const event of ['pull_request', 'push']) {
    const section = workflow.split(`  ${event}:\n`)[1]?.split(/\n  [a-z_]+:/)[0]
    assert.ok(section, `missing ${event}`)
    for (const path of ['apps/**', 'packages/**', 'pubspec.yaml', 'pubspec.lock', '.github/workflows/native-compile.yml', '.github/scripts/native-compile.test.mjs']) {
      assert.ok(section.includes(`- '${path}'`), `${event} missing ${path}`)
    }
  }
})
