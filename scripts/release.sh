#!/bin/sh
# Builds a universal, Developer ID-signed, notarized Pomodoro.dmg in dist/.
#   SIGN_IDENTITY  codesigning identity  (default: the Developer ID Application identity in the keychain)
#   NOTARY_PROFILE notarytool keychain profile (default: pomodoro-notary); set SKIP_NOTARIZE=1 to skip
set -eu
cd "$(dirname "$0")/.."

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity found" >&2; exit 1; }
PROFILE=${NOTARY_PROFILE:-pomodoro-notary}
TEAM=$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Pomodoro/Info.plist 2>/dev/null || echo 1.0)
DERIVED=build/release
APP=$DERIVED/Build/Products/Release/Pomodoro.app
DMG=dist/Pomodoro-$VERSION.dmg

echo "==> Building universal app, signing as: $IDENTITY"
xcodegen generate --quiet
xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -configuration Release \
    -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" \
    ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -quiet clean build

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Pomodoro"

echo "==> Creating $DMG"
rm -rf dist/dmg && mkdir -p dist/dmg
cp -R "$APP" dist/dmg/
ln -s /Applications dist/dmg/Applications
rm -f "$DMG"
hdiutil create -volname "Pomodoro" -srcfolder dist/dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf dist/dmg
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then
    echo "==> Skipping notarization: $DMG is signed but not notarized"
    exit 0
fi
echo "==> Notarizing (usually 1-5 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "==> Done: $DMG"
