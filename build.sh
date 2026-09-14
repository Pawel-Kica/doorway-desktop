#!/bin/bash
# Builds build/SimpleBlock.app: release binary + Info.plist (LSUIElement), ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product SimpleBlock
BIN="$(swift build -c release --show-bin-path)/SimpleBlock"
APP=build/SimpleBlock.app

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SimpleBlock"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.pawel.simple-block</string>
    <key>CFBundleName</key><string>SimpleBlock</string>
    <key>CFBundleDisplayName</key><string>Simple Block</string>
    <key>CFBundleExecutable</key><string>SimpleBlock</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
