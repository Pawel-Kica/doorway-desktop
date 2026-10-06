#!/bin/bash
# Builds Assets/AppIcon.icns, the bundle's own icon (Color in AppIcons.swift), from Assets/DoorwayColor.png in every
# standard size. Run from anywhere: app/scripts/make-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Assets/DoorwayColor.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Assets/DoorwayColor.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
echo "Wrote Assets/AppIcon.icns"
