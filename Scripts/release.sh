#!/usr/bin/env bash
#
# release.sh — build a Release LuxCurve.app and package it for a GitHub release,
# as both a drag-to-install .dmg and a plain .zip.
#
# No Developer ID / notarization (project decision): the app is ad-hoc signed
# and users allow it manually on first launch (see DISTRIBUTION.md). LuxCurve
# uses private Apple frameworks, so the Mac App Store is impossible regardless.
#
# We sign here in the script rather than during the Xcode build: macOS tags
# every source file with a `com.apple.provenance` xattr, which trips Xcode's
# in-build codesign ("resource fork ... detritus not allowed"). Building
# unsigned, stripping xattrs, then ad-hoc signing sidesteps that cleanly.
#
# Usage:  ./Scripts/release.sh   →   build/LuxCurve.dmg  and  build/LuxCurve.zip

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build
DD="$BUILD/dd"
APP="$DD/Build/Products/Release/LuxCurve.app"
STAGE="$BUILD/dmg"
DMG="$BUILD/LuxCurve.dmg"
ZIP="$BUILD/LuxCurve.zip"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "▸ Building (Release, unsigned)…"
xcodebuild -project LuxCurve.xcodeproj -scheme LuxCurve -configuration Release \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO build

echo "▸ Ad-hoc signing…"
xattr -cr "$APP"                       # strip provenance/quarantine attributes
codesign --force --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "▸ Building drag-to-install disk image…"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # so the window shows a drop target
hdiutil create -volname "LuxCurve" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo "▸ Zipping (alternative download)…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ Done:"
echo "    $DMG"
echo "    $ZIP"
