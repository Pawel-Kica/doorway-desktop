#!/bin/bash
# Builds /Applications/Simple Block.app (so Raycast and Spotlight find it): release binary + Info.plist, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product SimpleBlock
BIN="$(swift build -c release --show-bin-path)/SimpleBlock"
APP="/Applications/Simple Block.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Copied next to the old binary and renamed over it: writing into the binary of a running Simple Block kills it.
# This way the running one keeps its copy and the new build starts on the next launch.
cp "$BIN" "$APP/Contents/MacOS/SimpleBlock.new"
mv -f "$APP/Contents/MacOS/SimpleBlock.new" "$APP/Contents/MacOS/SimpleBlock"
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
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A picked app icon is an Icon\r file in the bundle root plus Finder info, which codesign refuses. The app puts it back
# at launch.
if [ -e "$APP/Icon"$'\r' ]; then mv -f "$APP/Icon"$'\r' /tmp/; fi
xattr -cr "$APP"
# Signed with the Apple Development certificate when there is one: macOS ties the Accessibility grant to the signature,
# and an ad-hoc one changes with every build, which would drop the grant each time.
IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2; exit }')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
