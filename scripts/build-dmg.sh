#!/bin/bash
# Builds build/Jot-<version>.dmg: a universal app signed with a Developer ID certificate,
# in a disk image that is notarized by Apple and has the ticket stapled to it.
#
# Signing identity:  $JOT_RELEASE_IDENTITY, else the first line of .release-identity
# Notary profile:    $JOT_NOTARY_PROFILE, else the first line of .notary-profile
#                    (a keychain profile created with `xcrun notarytool store-credentials`)
# Without a notary profile the image is built and signed but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

setting() { # setting <ENV_VALUE> <file>
    if [ -n "$1" ]; then
        echo "$1"
    elif [ -f "$2" ]; then
        sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$2"
    fi
}

IDENTITY="$(setting "${JOT_RELEASE_IDENTITY:-}" .release-identity)"
PROFILE="$(setting "${JOT_NOTARY_PROFILE:-}" .notary-profile)"
if [ -z "$IDENTITY" ]; then
    echo "No release identity. Set JOT_RELEASE_IDENTITY or create .release-identity." >&2
    exit 1
fi

JOT_SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh --universal

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Jot-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Jot.app "$STAGE/Jot.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Jot" -srcfolder "$STAGE" -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -z "$PROFILE" ]; then
    echo "Built $DMG (signed, not notarized: no notary profile)"
    exit 0
fi

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
echo "Built $DMG (signed and notarized)"
