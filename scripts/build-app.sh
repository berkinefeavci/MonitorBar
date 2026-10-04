#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx12.0" --scratch-path ".build/$arch"
done
app="$PWD/dist/PanelLight.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create .build/arm64/out/Products/Release/MonitorBar \
             .build/x86_64/out/Products/Release/MonitorBar \
     -output "$app/Contents/MacOS/MonitorBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun actool "$PWD/Resources/PanelLight.icon" \
  --compile "$app/Contents/Resources" \
  --output-format human-readable-text --notices --warnings \
  --output-partial-info-plist "$PWD/.build/PanelLight-icon-info.plist" \
  --app-icon PanelLight --platform macosx \
  --minimum-deployment-target 12.0 --target-device mac
test -s "$app/Contents/Resources/PanelLight.icns"
codesign --force --sign - "$app"
echo "$app"
