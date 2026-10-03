#!/bin/bash
# Rebuilds dist/ for SideStore: the IPA plus the source file SideStore subscribes to.
# Run it after ./scripts/build-ios.sh ipa, then commit and push.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools

SLUG=$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
[ -z "$SLUG" ] && { echo "no origin remote yet — push the repo first"; exit 1; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)
RAW="https://raw.githubusercontent.com/$SLUG/$BRANCH"

mkdir -p dist
cp build/LifeTracker.ipa dist/LifeTracker.ipa
cp LifeTracker/Assets.xcassets/AppIcon.appiconset/icon_1024.png dist/icon.png

SIZE=$(stat -f%z dist/LifeTracker.ipa)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/ios.noindex/LifeTracker.app/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/ios.noindex/LifeTracker.app/Info.plist)
DATE=$(date -u +%Y-%m-%d)
NOTES=${NOTES:-"Home and lock screen widgets, a Mac menu bar with today in it, and a journey you can start on a future date."}

cat > dist/source.json <<JSON
{
  "name": "Life Tracker",
  "identifier": "com.soubick.lifetracker.source",
  "subtitle": "The Life Tracker app, straight from its repo",
  "iconURL": "$RAW/dist/icon.png",
  "website": "https://github.com/$SLUG",
  "tintColor": "5C6BF2",
  "apps": [
    {
      "name": "Life Tracker",
      "bundleIdentifier": "com.soubick.lifetracker",
      "developerName": "Soubick",
      "subtitle": "Your Google Sheet, as a native app",
      "localizedDescription": "Your day, your habits and the long things, in one place. Today, Tomorrow and Yesterday with drag-to-reorder, habits with streaks and a month grid, a journey with a reverse countdown and daily proof photos, goals, body log, notes and the log. Subscribes your timed tasks to Apple or Google Calendar, reminds you before one starts, and puts the day on your home and lock screens.",
      "iconURL": "$RAW/dist/icon.png",
      "tintColor": "5C6BF2",
      "category": "lifestyle",
      "screenshotURLs": [],
      "version": "$VERSION",
      "versionDate": "${DATE}T00:00:00Z",
      "versionDescription": "$NOTES",
      "downloadURL": "$RAW/dist/LifeTracker.ipa",
      "size": $SIZE,
      "versions": [
        {
          "version": "$VERSION",
          "buildVersion": "$BUILD",
          "date": "$DATE",
          "localizedDescription": "$NOTES",
          "downloadURL": "$RAW/dist/LifeTracker.ipa",
          "size": $SIZE,
          "minOSVersion": "18.0"
        }
      ]
    }
  ],
  "news": []
}
JSON

echo "dist/source.json  →  $RAW/dist/source.json"
echo "add that URL in SideStore ▸ Sources ▸ +"
