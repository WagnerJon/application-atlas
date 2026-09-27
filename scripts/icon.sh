#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f build/AppIcon.icns && build/AppIcon.icns -nt Assets/AppIcon.png ]]; then
    exit 0
fi
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns
