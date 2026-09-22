#!/usr/bin/env pwsh
# Stages the bundled pi runtime next to the Flutter build output so the app
# runs with no `pi` on PATH.
#
# Layout produced (next to pi_studio.exe / the linux bundle):
#   pi_runtime/
#     PI_VERSION            pinned pi version + source, for logs and debugging
#     package.json          required: anchors getPackageDir() asset resolution
#     bin/node(.exe)        Node 22, copied from the runner's own toolchain
#     dist/bundle/...       pi bundle (rpc-entry.js + chunks), from npm
#     dist/modes/...        theme + interactive assets resolved via getPackageDir()
#     dist/core/export-html HTML export template resolved via getPackageDir()
#     node_modules/
#       @earendil-works/chord/  hard static import (audited; smoke test
#                               below fails the stage if a future pi adds one)
#       jiti/                   lazy require for TS extension loading
#       @silvia-odwyer/photon-node/   image wasm; graceful fallback without it
#
# Inputs (env):
#   PI_STUDIO_PI_DIR   root of an installed @earendil-works/pi-coding-agent
#                      package (the dir containing package.json + dist/).
#                      Default: the npm-global install next to `pi` on PATH.
#   PI_STUDIO_NODE_EXE path to a node 22 binary. Default: `node` on PATH,
#                      else the node bundled with a managed pi install.
#
# Usage:
#   flutter build windows --release
#   ./tool/stage_pi_runtime.ps1 -OutputDir build/windows/x64/runner/Release
#
# The release workflow runs this on each platform before packaging. Local dev
# builds skip it (PiClient falls back to `pi` on PATH), which is why this is
# a manual step and not a build hook.
param(
  [string]$OutputDir = 'build/windows/x64/runner/Release'
)

$ErrorActionPreference = 'Stop'

function Find-PiDir {
  if ($env:PI_STUDIO_PI_DIR -and (Test-Path (Join-Path $env:PI_STUDIO_PI_DIR 'package.json'))) {
    return $env:PI_STUDIO_PI_DIR
  }
  $pi = Get-Command pi -ErrorAction SilentlyContinue
  if (-not $pi) { throw 'pi not found on PATH; set PI_STUDIO_PI_DIR to the package root' }
  # npm shims resolve to the real cli.js; walk up to the package root.
  $target = $pi.Source
  if ($target -like '*.cmd' -or $target -like '*.ps1') {
    $dir = Split-Path $target
    $cli = Join-Path $dir 'node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js'
    if (Test-Path $cli) {
      return (Resolve-Path (Join-Path $dir 'node_modules/@earendil-works/pi-coding-agent')).Path
    }
  }
  throw "cannot locate pi package root from $($pi.Source); set PI_STUDIO_PI_DIR"
}

function Find-NodeExe([string]$piDir) {
  if ($env:PI_STUDIO_NODE_EXE -and (Test-Path $env:PI_STUDIO_NODE_EXE)) {
    return $env:PI_STUDIO_NODE_EXE
  }
  # Managed installs (pi.dev/install.sh, pi-node) ship their own node next
  # to node_modules/.
  $managed = Join-Path (Split-Path $piDir) '../node.exe'
  if (Test-Path $managed) { return (Resolve-Path $managed).Path }
  $managed = Join-Path (Split-Path $piDir) '../node'
  if (Test-Path $managed) { return (Resolve-Path $managed).Path }
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) { return $node.Source }
  throw 'node not found; set PI_STUDIO_NODE_EXE'
}

$piDir = Find-PiDir
$nodeExe = Find-NodeExe $piDir
$pkg = Get-Content (Join-Path $piDir 'package.json') -Raw | ConvertFrom-Json
$version = $pkg.version
Write-Host "Staging pi $version from $piDir"
Write-Host "Node: $nodeExe"

$nodeVersion = & $nodeExe --version
if ($nodeVersion -notmatch '^v(22|24)\.') {
  throw "node $nodeVersion is not Node 22/24 (bundle needs node:sqlite); set PI_STUDIO_NODE_EXE"
}

$dest = Join-Path $OutputDir 'pi_runtime'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# The bundle resolves dist-relative assets (themes, export-html template,
# interactive assets, package.json) via getPackageDir(), which walks up from
# the entry file to the first dir containing package.json. So the staged tree
# must be a faithful package root: package.json at top, dist/ and
# node_modules/ alongside it. A bare dist/bundle copy would walk past the
# runtime into the app dir and silently miss every asset.
Copy-Item (Join-Path $piDir 'package.json') (Join-Path $dest 'package.json') -Force
$bundle = Join-Path $piDir 'dist/bundle'
foreach ($name in @('rpc-entry.js', 'cli.js', 'cli-runtime.js', 'index.js', 'chunks')) {
  $src = Join-Path $bundle $name
  if (-not (Test-Path $src)) { throw "missing $src; is pi $version intact?" }
  Copy-Item $src (Join-Path $dest "dist/bundle/$name") -Recurse -Force
}
foreach ($asset in @('dist/modes/interactive/theme', 'dist/core/export-html', 'dist/modes/interactive/assets')) {
  $src = Join-Path $piDir $asset
  if (-not (Test-Path $src)) { throw "missing $src; is pi $version intact?" }
  Copy-Item $src (Join-Path $dest $asset) -Recurse -Force
}

$photon = Join-Path $piDir 'node_modules/@silvia-odwyer/photon-node'
if (Test-Path $photon) {
  Copy-Item $photon `
    (Join-Path $dest 'node_modules/@silvia-odwyer/photon-node') -Recurse -Force
} else {
  Write-Warning 'photon-node not found; non-PNG image conversion will be skipped'
}

# Hard runtime imports of the bundle, resolved via createRequire from the
# chunk files (audited for this pi version; the smoke test below fails the
# stage if a future pi adds another one):
#   @earendil-works/chord/context  static import, needed even for --help
#   jiti                            lazy require for TS extension loading
foreach ($dep in @('@earendil-works/chord', 'jiti')) {
  $src = Join-Path $piDir "node_modules/$dep"
  if (-not (Test-Path $src)) { throw "missing $src; is pi $version intact?" }
  Copy-Item $src (Join-Path $dest "node_modules/$dep") -Recurse -Force
}

$bin = Join-Path $dest 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item $nodeExe (Join-Path $bin (Split-Path $nodeExe -Leaf)) -Force

# Smoke test: boot the staged runtime standalone. Catches a missing runtime
# dep (e.g. a new bare import in a future pi) here, not in a user's release.
# Two boots: the rpc entry (session backend) and cli.js (package manager) —
# the app shells out to both, and cli.js pulls extra modules
# (update/install paths) that rpc-entry never touches.
$nodeBin = Join-Path $bin (Split-Path $nodeExe -Leaf)
& $nodeBin (Join-Path $dest 'dist/bundle/rpc-entry.js') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'staged runtime failed to boot' }
& $nodeBin (Join-Path $dest 'dist/bundle/cli.js') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'staged cli.js failed to boot' }

"$($pkg.name) $version staged $(Get-Date -Format o) from $piDir" |
  Set-Content (Join-Path $dest 'PI_VERSION')

Write-Host "Staged:"
Get-ChildItem $dest -Recurse -File |
  ForEach-Object { Write-Host ("  {0}  {1:N1} MB" -f $_.FullName.Substring($dest.Length + 1), ($_.Length / 1MB)) }
