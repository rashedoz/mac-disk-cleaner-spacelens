#!/bin/bash
# Builds a universal (Apple silicon + Intel) release binary and wraps it in build/SpaceLens.app.
# Pass --dmg to also write the disk image the landing page links to.
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

if [ "${1:-}" = "--dmg" ]; then
    # A disk image holding the app next to a shortcut to /Applications,
    # so installing is one drag.
    STAGE="build/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE" docs/download
    cp -R "$APP" "$STAGE/SpaceLens.app"
    ln -s /Applications "$STAGE/Applications"
    rm -f docs/download/SpaceLens.dmg
    hdiutil create -volname "SpaceLens" -srcfolder "$STAGE" -ov -format UDZO \
        docs/download/SpaceLens.dmg >/dev/null
    rm -rf "$STAGE"
    echo "Wrote docs/download/SpaceLens.dmg"
fi
