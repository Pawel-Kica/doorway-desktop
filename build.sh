#!/bin/bash
# Builds /Applications/Doorway Desktop.app (so Raycast and Spotlight find it): release binary + Info.plist, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product DoorwayDesktop
BIN="$(swift build -c release --show-bin-path)/DoorwayDesktop"
APP="/Applications/Doorway Desktop.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Copied next to the old binary and renamed over it: writing into the binary of a running Doorway Desktop kills it.
# This way the running one keeps its copy and the new build starts on the next launch.
cp "$BIN" "$APP/Contents/MacOS/DoorwayDesktop.new"
mv -f "$APP/Contents/MacOS/DoorwayDesktop.new" "$APP/Contents/MacOS/DoorwayDesktop"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Doorway's color icon: the Color app icon pick, and the icon on the prompt.
cp Assets/DoorwayColor.png "$APP/Contents/Resources/DoorwayColor.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.pawel.doorway-desktop</string>
    <key>CFBundleName</key><string>Doorway Desktop</string>
    <key>CFBundleDisplayName</key><string>Doorway Desktop</string>
    <key>CFBundleExecutable</key><string>DoorwayDesktop</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- The look from before macOS 26. Built with the 26 SDK the sidebar turns into a floating panel, a second border inside the window's. -->
    <key>UIDesignRequiresCompatibility</key><true/>
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
