#!/bin/bash
# Builds build/Jot.app from the release binary.
#   --install    also replaces /Applications/Jot.app
#   --universal  builds for both Apple silicon and Intel
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
ARCH_FLAGS=()
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Jot"

APP=build/Jot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Jot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Signing identity: $JOT_SIGN_IDENTITY, else the first line of .signing-identity, else ad hoc.
# A real certificate keeps the login item and other macOS permissions across rebuilds.
IDENTITY="${JOT_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ -f .signing-identity ]; then
    IDENTITY="$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' .signing-identity)"
fi
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
    echo "Built $APP (signed ad hoc)"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    echo "Built $APP (signed with a certificate)"
fi

if [ "$INSTALL" = 1 ]; then
    # Only ask a running app to quit; "tell application" would otherwise launch it.
    if pgrep -x Jot >/dev/null; then
        osascript -e 'tell application "Jot" to quit' 2>/dev/null || true
    fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x Jot >/dev/null || break
        sleep 0.5
    done
    pkill -x Jot 2>/dev/null || true
    rm -rf /Applications/Jot.app
    cp -R "$APP" /Applications/Jot.app
    echo "Installed /Applications/Jot.app"
fi
