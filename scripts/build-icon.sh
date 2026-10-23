#!/bin/bash
# Package the approved artwork at native macOS icon sizes without redrawing it.
set -euo pipefail
cd "$(dirname "$0")/.."
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/minitypeless-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT
mkdir "$icon_work/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" artwork/AppIcon-source.png --out "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" artwork/AppIcon-source.png --out "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work/AppIcon.iconset" -o MiniTypelessSecure/Resources/AppIcon.icns
