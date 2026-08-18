#!/bin/bash
# Release build: regenerate the Xcode project and build the app (with the
# embedded CLI). Output: build/dd/Build/Products/Release/CleanDock.app
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen
xcodebuild -project "CleanDock.xcodeproj" -scheme "CleanDock" \
  -configuration Release -derivedDataPath build/dd build

echo
echo "Built: build/dd/Build/Products/Release/CleanDock.app"
