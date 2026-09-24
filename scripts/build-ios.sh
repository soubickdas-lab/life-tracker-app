#!/bin/bash
# iPhone build — talks to the toolchain directly, so no Xcode licence prompt.
#   ./scripts/build-ios.sh sim   → build, install and launch in the iPhone simulator
#   ./scripts/build-ios.sh ipa   → unsigned build/LifeTracker.ipa for SideStore
set -e
cd "$(dirname "$0")/.."
MODE=${1:-ipa}
APP_VERSION=$(cat VERSION 2>/dev/null || echo 1.0)
BUILD_NUMBER=$(DEVELOPER_DIR=/Library/Developer/CommandLineTools git rev-list --count HEAD 2>/dev/null || echo 1)
XC=/Applications/Xcode.app/Contents/Developer
SWIFTC=$XC/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
SRC="LifeTracker/*.swift LifeTracker/Views/*.swift"

if [ "$MODE" = "sim" ]; then
  SDK=$XC/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
  TARGET=arm64-apple-ios18.0-simulator
  PLATFORM=iPhoneSimulator
  OUT=build/sim/LifeTracker.app
else
  SDK=$XC/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
  TARGET=arm64-apple-ios18.0
  PLATFORM=iPhoneOS
  OUT=build/ios/LifeTracker.app
fi

rm -rf "$OUT"; mkdir -p "$OUT"

$SWIFTC -parse-as-library -O -target "$TARGET" -sdk "$SDK" \
  -o "$OUT/LifeTracker" $SRC

# the icon, at the sizes the home screen and Settings ask for
ICON=LifeTracker/Assets.xcassets/AppIcon.appiconset/icon_1024.png
if [ -f "$ICON" ]; then
  for pair in "120 AppIcon60x60@2x" "180 AppIcon60x60@3x" "152 AppIcon76x76@2x~ipad" \
              "167 AppIcon83.5x83.5@2x~ipad" "80 AppIcon40x40@2x" "58 AppIcon29x29@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$ICON" --out "$OUT/$2.png" >/dev/null
  done
fi

cat > "$OUT/Info.plist" <<PLIST
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
	<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>MinimumOSVersion</key><string>18.0</string>
	<key>LSRequiresIPhoneOS</key><true/>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>CADisableMinimumFrameDurationOnPhone</key><true/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
	<key>CFBundleSupportedPlatforms</key><array><string>$PLATFORM</string></array>
	<key>CFBundleIcons</key>
	<dict><key>CFBundlePrimaryIcon</key><dict>
		<key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
		<key>UIPrerenderedIcon</key><false/>
	</dict></dict>
	<key>CFBundleURLTypes</key>
	<array><dict>
		<key>CFBundleURLName</key><string>com.soubick.lifetracker</string>
		<key>CFBundleURLSchemes</key><array><string>lifetracker</string></array>
	</dict></array>
	<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$OUT" >/dev/null 2>&1 || true

if [ "$MODE" = "sim" ]; then
  echo "app: $OUT"
  exit 0
fi

rm -rf build/Payload build/LifeTracker.ipa
mkdir -p build/Payload
cp -R "$OUT" build/Payload/
(cd build && zip -qry LifeTracker.ipa Payload)
rm -rf build/Payload
echo "ipa: $(pwd)/build/LifeTracker.ipa  — install this through SideStore"
