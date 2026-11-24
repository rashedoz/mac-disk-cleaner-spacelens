#!/bin/bash
# Builds a universal (Apple silicon + Intel) release binary and wraps it in build/SpaceLens.app.
# Pass --zip to also write the download archive the landing page links to.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64

APP="build/SpaceLens.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/SpaceLens "$APP/Contents/MacOS/SpaceLens"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [ "${1:-}" = "--zip" ]; then
    mkdir -p docs/download
    rm -f docs/download/SpaceLens.zip
    ditto -c -k --keepParent "$APP" docs/download/SpaceLens.zip
    echo "Wrote docs/download/SpaceLens.zip"
fi
