#!/usr/bin/env bash
# Stages the bundled pi runtime next to the Flutter build output so the app
# runs with no `pi` on PATH. Linux counterpart of tool/stage_pi_runtime.ps1;
# see that file for the layout and rationale.
#
# Inputs (env): PI_STUDIO_PI_DIR, PI_STUDIO_NODE_EXE (same semantics).
# Also set PI_STUDIO_NPM_DIR to the npm package directory from that Node install.
#
# Usage:
#   flutter build linux --release
#   ./tool/stage_pi_runtime.sh build/linux/x64/release/bundle
set -euo pipefail

OUT="${1:-build/linux/x64/release/bundle}"

find_pi_dir() {
  if [[ -n "${PI_STUDIO_PI_DIR:-}" && -f "$PI_STUDIO_PI_DIR/package.json" ]]; then
    echo "$PI_STUDIO_PI_DIR"
    return
  fi
  if ! command -v pi >/dev/null 2>&1; then
    echo "pi not found on PATH; set PI_STUDIO_PI_DIR to the package root" >&2
    exit 1
  fi
  local pi_path
  pi_path="$(command -v pi)"
  # npm shims are symlinks into node_modules/.bin; resolve to package root.
  local real
  real="$(readlink -f "$pi_path")"
  local pkg_dir
  pkg_dir="$(dirname "$(dirname "$real")")/@earendil-works/pi-coding-agent"
  if [[ -f "$pkg_dir/package.json" ]]; then
    echo "$pkg_dir"
    return
  fi
  echo "cannot locate pi package root from $pi_path; set PI_STUDIO_PI_DIR" >&2
  exit 1
}

find_node_exe() {
  local pi_dir="$1"
  if [[ -n "${PI_STUDIO_NODE_EXE:-}" && -x "$PI_STUDIO_NODE_EXE" ]]; then
    echo "$PI_STUDIO_NODE_EXE"
    return
  fi
  local managed
  managed="$(readlink -f "$pi_dir/../node" 2>/dev/null || true)"
  if [[ -n "$managed" && -x "$managed" ]]; then
    echo "$managed"
    return
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return
  fi
  echo "node not found; set PI_STUDIO_NODE_EXE" >&2
  exit 1
}

PI_DIR="$(find_pi_dir)"
NODE_EXE="$(find_node_exe "$PI_DIR")"
VERSION="$(node -p "require('$PI_DIR/package.json').version" 2>/dev/null || grep -m1 '"version"' "$PI_DIR/package.json")"
echo "Staging pi $VERSION from $PI_DIR"
echo "Node: $NODE_EXE"

NODE_VERSION="$("$NODE_EXE" --version)"
if [[ ! "$NODE_VERSION" =~ ^v(22|24)\. ]]; then
  echo "node $NODE_VERSION is not Node 22/24 (bundle needs node:sqlite); set PI_STUDIO_NODE_EXE" >&2
  exit 1
fi

DEST="$OUT/pi_runtime"
rm -rf "$DEST"
mkdir -p "$DEST/dist/bundle" "$DEST/bin"

# See stage_pi_runtime.ps1: the staged tree must be a faithful package root
# (package.json at top) because getPackageDir() resolves assets by walking up
# from the entry file to the first dir containing package.json.
cp "$PI_DIR/package.json" "$DEST/package.json"
for name in rpc-entry.js cli.js cli-runtime.js index.js chunks; do
  if [[ ! -e "$PI_DIR/dist/bundle/$name" ]]; then
    echo "missing $PI_DIR/dist/bundle/$name; is the pi install intact?" >&2
    exit 1
  fi
  cp -r "$PI_DIR/dist/bundle/$name" "$DEST/dist/bundle/$name"
done
for asset in dist/modes/interactive/theme dist/core/export-html dist/modes/interactive/assets; do
  if [[ ! -e "$PI_DIR/$asset" ]]; then
    echo "missing $PI_DIR/$asset; is the pi install intact?" >&2
    exit 1
  fi
  mkdir -p "$DEST/$(dirname "$asset")"
  cp -r "$PI_DIR/$asset" "$DEST/$asset"
done

if [[ -d "$PI_DIR/node_modules/@silvia-odwyer/photon-node" ]]; then
  mkdir -p "$DEST/node_modules/@silvia-odwyer"
  cp -r "$PI_DIR/node_modules/@silvia-odwyer/photon-node" \
    "$DEST/node_modules/@silvia-odwyer/photon-node"
else
  echo "warning: photon-node not found; non-PNG image conversion will be skipped" >&2
fi

# Hard runtime imports of the bundle, resolved via createRequire from the
# chunk files (audited for this pi version; the smoke test below fails the
# stage if a future pi adds another one):
#   @earendil-works/chord/context  static import, needed even for --help
#   jiti                            lazy require for TS extension loading
for dep in @earendil-works/chord jiti; do
  if [[ ! -e "$PI_DIR/node_modules/$dep" ]]; then
    echo "missing $PI_DIR/node_modules/$dep; is the pi install intact?" >&2
    exit 1
  fi
  mkdir -p "$DEST/node_modules/$(dirname "$dep")"
  cp -r "$PI_DIR/node_modules/$dep" "$DEST/node_modules/$dep"
done

if [[ -z "${PI_STUDIO_NPM_DIR:-}" || ! -f "$PI_STUDIO_NPM_DIR/bin/npm-cli.js" ]]; then
  echo "npm not found; set PI_STUDIO_NPM_DIR to the Node distribution npm directory" >&2
  exit 1
fi
mkdir -p "$DEST/node_modules/npm"
cp -r "$PI_STUDIO_NPM_DIR"/. "$DEST/node_modules/npm/"

cp "$NODE_EXE" "$DEST/bin/node"
chmod +x "$DEST/bin/node"

# Smoke test: boot the staged runtime standalone. Catches a missing runtime
# dep (e.g. a new bare import in a future pi) here, not in a user's release.
# Two boots: the rpc entry (session backend) and cli.js (package manager) —
# the app shells out to both, and cli.js pulls extra modules (update/install
# paths) that rpc-entry never touches.
"$DEST/bin/node" "$DEST/dist/bundle/rpc-entry.js" --help >/dev/null || {
  echo "staged runtime failed to boot; see above" >&2
  exit 1
}
"$DEST/bin/node" "$DEST/dist/bundle/cli.js" --help >/dev/null || {
  echo "staged cli.js failed to boot; see above" >&2
  exit 1
}
"$DEST/bin/node" "$DEST/node_modules/npm/bin/npm-cli.js" --version >/dev/null || {
  echo "staged npm failed to boot; see above" >&2
  exit 1
}

echo "$(grep -m1 '"name"' "$PI_DIR/package.json" | cut -d'"' -f4) $VERSION staged $(date -u +%FT%TZ) from $PI_DIR" > "$DEST/PI_VERSION"

echo "Staged:"
find "$DEST" -type f -printf '.' | wc -c | xargs printf '  %s files\n'
du -sh "$DEST" | cut -f1 | xargs printf '  %s total\n'
