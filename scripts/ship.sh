#!/bin/bash
# Gets a new build onto the phone in one go:
#   ./scripts/ship.sh          build, refresh dist/, commit, push
#   ./scripts/ship.sh 1.1      set the version first, then the same
#
# It sets DEVELOPER_DIR itself, so plain `git` never hits Xcode's licence prompt.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export PATH="$HOME/bin:$PATH"          # gh lives here

[ -n "$1" ] && echo "$1" > VERSION
VERSION=$(cat VERSION)

SHIPPED=$(node -e 'try{console.log(require("./dist/source.json").apps[0].version)}catch(e){console.log("")}')
if [ "$VERSION" = "$SHIPPED" ]; then
  echo "⚠️  Version is still $VERSION — SideStore only offers an update when the number changes."
  echo "    Run:  ./scripts/ship.sh 1.1"
fi

./scripts/build-ios.sh ipa
./scripts/make-source.sh

git add -A
if git diff --cached --quiet; then
  echo "nothing new to ship"
  exit 0
fi
git commit -qm "Life Tracker $VERSION"
git push -q origin "$(git rev-parse --abbrev-ref HEAD)"
echo
echo "✅ pushed — SideStore will see version $VERSION at"
echo "   https://raw.githubusercontent.com/$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')/$(git rev-parse --abbrev-ref HEAD)/dist/source.json"
