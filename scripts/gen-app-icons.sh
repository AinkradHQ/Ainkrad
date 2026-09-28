#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/AppIconSources"
OUT="$ROOT/Sources/Ainkrad/Resources/AppIcons"
mkdir -p "$OUT"

compose() { # <SourceIconBaseName> <output-name>
  local name="$1" out="$2"
  local tmp; tmp="$(mktemp -d)"
  # Copy the .icon to a temp dir under the name actool should use as the app-icon.
  cp -R "$SRC/${name}.icon" "$tmp/AppIcon.icon"
  # actool requires the --compile output directory to already exist.
  mkdir -p "$tmp/out"
  xcrun actool "$tmp/AppIcon.icon" \
    --compile "$tmp/out" \
    --app-icon AppIcon \
    --platform macosx --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$tmp/plist" \
    --output-format human-readable-text >/dev/null
  cp "$tmp/out/AppIcon.icns" "$OUT/${out}.icns"
  rm -rf "$tmp"
  echo "composed $out.icns"
}

compose Blue-Light   blue-light
compose Blue-Dark    blue-dark
compose Purple-Light purple-light
compose Purple-Dark  purple-dark
echo "done → $OUT"
