#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="dist/MonitorBar.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/MonitorBar "$app/Contents/MacOS/MonitorBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$PWD/$app"
