#!/bin/bash
# Builds a runnable Life Tracker.app with the Command Line Tools only.
# Handy before Xcode's licence is accepted; the real build is the xcodebuild one in README.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=${1:-build/mac.noindex/Life Tracker.app}
APP_VERSION=$(cat VERSION 2>/dev/null || echo 1.0)

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

xcrun swiftc -parse-as-library -O \
  -target arm64-apple-macos15.0 -sdk "$SDK" \
  -o "$OUT/Contents/MacOS/LifeTracker" \
  LifeTracker/*.swift LifeTracker/Views/*.swift

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Life Tracker</string>
	<key>CFBundleDisplayName</key><string>Life Tracker</string>
	<key>CFBundleExecutable</key><string>LifeTracker</string>
	<key>CFBundleIdentifier</key><string>com.soubick.lifetracker</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>NSMicrophoneUsageDescription</key><string>So you can record a voice message for the assistant instead of typing.</string>
	<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>CFBundleURLTypes</key>
	<array><dict>
		<key>CFBundleURLName</key><string>com.soubick.lifetracker</string>
		<key>CFBundleURLSchemes</key><array><string>lifetracker</string></array>
	</dict></array>
	<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

[ -f build/LifeTracker.icns ] && cp build/LifeTracker.icns "$OUT/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$OUT" >/dev/null 2>&1 || true
echo "built: $OUT"

# One copy that the Dock, Spotlight and Launchpad all agree on. The build folder's
# own copy is taken off the Mac's list of apps, so there is never a second one.
#   INSTALL=0 ./scripts/build-mac.sh   builds without touching the installed app
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$(pwd)/$OUT" >/dev/null 2>&1 || true

if [ "${INSTALL:-1}" = "1" ] && [ -z "$1" ]; then
  DEST="/Applications/Life Tracker.app"
  [ -w /Applications ] || { DEST="$HOME/Applications/Life Tracker.app"; mkdir -p "$HOME/Applications"; }
  rm -rf "$DEST"
  cp -R "$OUT" "$DEST"
  "$LSREG" -f "$DEST" >/dev/null 2>&1 || true
  echo "installed: $DEST"
fi
