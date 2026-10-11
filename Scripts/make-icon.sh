#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
swift "$ROOT/Scripts/art.swift" icon "$TMP/icon-1024.png" 1024
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
echo "✓ Resources/AppIcon.icns"
