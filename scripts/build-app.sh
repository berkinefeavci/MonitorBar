#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --triple arm64-apple-macosx12.0 --scratch-path .build/arm64
app="$PWD/dist/PanelLight.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64/out/Products/Release/MonitorBar "$app/Contents/MacOS/MonitorBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/en.lproj Resources/tr.lproj "$app/Contents/Resources/"
xcrun actool "$PWD/Resources/PanelLight.icon" \
  --compile "$app/Contents/Resources" \
  --output-format human-readable-text --notices --warnings \
  --output-partial-info-plist "$PWD/.build/PanelLight-icon-info.plist" \
  --app-icon PanelLight --platform macosx \
  --minimum-deployment-target 12.0 --target-device mac
test -s "$app/Contents/Resources/PanelLight.icns"
codesign --force --sign - "$app"
echo "$app"
