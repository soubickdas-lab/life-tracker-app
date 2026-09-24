#!/bin/bash
# Builds a runnable Life Tracker.app with the Command Line Tools only.
# Handy before Xcode's licence is accepted; the real build is the xcodebuild one in README.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=${1:-build/Life Tracker.app}

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
	<key>CFBundleShortVersionString</key><string>1.0</string>
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
