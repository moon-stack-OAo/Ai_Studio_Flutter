# Clear Flutter build caches for this workspace (not app runtime user data).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tool/clear-cache.ps1
# Optional: -SkipPubGet

[CmdletBinding()]
param(
  [switch]$SkipPubGet
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

Write-Host "Repo root: $root"
Write-Host "Clearing Flutter build caches..."

$packages = @(
  '.'
  'apps\desktop_fluent'
  'apps\mobile_material'
  'packages\core'
  'packages\design_fluent'
  'packages\design_material'
)

function Remove-CachePath([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  try {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    Write-Host "  removed $path"
  } catch {
    Write-Warning "  failed to remove $path : $_"
  }
}

foreach ($rel in $packages) {
  $dir = if ($rel -eq '.') { $root } else { Join-Path $root $rel }
  $pubspec = Join-Path $dir 'pubspec.yaml'
  if (-not (Test-Path -LiteralPath $pubspec)) { continue }
  Write-Host "--- flutter clean: $rel ---"
  Push-Location -LiteralPath $dir
  try {
    & flutter clean
  } catch {
    Write-Warning "flutter clean failed ($rel): $_"
  } finally {
    Pop-Location
  }
}

$extraNames = @(
  'build'
  '.dart_tool'
  '.flutter-plugins'
  '.flutter-plugins-dependencies'
  '.packages'
  'ephemeral'
)

foreach ($rel in $packages) {
  $dir = if ($rel -eq '.') { $root } else { Join-Path $root $rel }
  foreach ($name in $extraNames) {
    Remove-CachePath (Join-Path $dir $name)
  }
  Remove-CachePath (Join-Path $dir 'windows\flutter\ephemeral')
  Remove-CachePath (Join-Path $dir 'macos\Flutter\ephemeral')
  Remove-CachePath (Join-Path $dir 'linux\flutter\ephemeral')
  Remove-CachePath (Join-Path $dir 'ios\Flutter\ephemeral')
  Remove-CachePath (Join-Path $dir 'android\.gradle')
  Remove-CachePath (Join-Path $dir 'android\app\build')
  Remove-CachePath (Join-Path $dir 'android\build')
}

Remove-CachePath (Join-Path $root '.idea\caches')

if (-not $SkipPubGet) {
  Write-Host '--- flutter pub get (workspace root) ---'
  & flutter pub get
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "flutter pub get exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
  }
}

Write-Host 'Done. App runtime data was not cleared.'
Write-Host 'Next: cd apps/desktop_fluent; flutter run -d windows --release'
