#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx12.0" --scratch-path ".build/$arch"
done
app="dist/MonitorBar.app"
mkdir -p "$app/Contents/MacOS"
lipo -create .build/arm64/out/Products/Release/MonitorBar \
             .build/x86_64/out/Products/Release/MonitorBar \
     -output "$app/Contents/MacOS/MonitorBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$PWD/$app"
