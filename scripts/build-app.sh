#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/nika-desktop-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/nika-desktop-swift"
NIKA_BUILD_CONFIGURATION="${NIKA_BUILD_CONFIGURATION:-release}"
case "$NIKA_BUILD_CONFIGURATION" in
  debug|release) ;;
  *) printf 'NIKA_BUILD_CONFIGURATION must be debug or release\n' >&2; exit 1 ;;
esac
swift build --package-path "$DESKTOP_ROOT" --disable-sandbox -c "$NIKA_BUILD_CONFIGURATION"
APP="$DESKTOP_ROOT/build/NIKA Desktop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$DESKTOP_ROOT/.build/$NIKA_BUILD_CONFIGURATION/NIKADesktop" "$APP/Contents/MacOS/NIKADesktop"
mkdir -p "$APP/Contents/Resources/Mascot"
cp "$DESKTOP_ROOT/Sources/NIKADesktop/Resources/Mascot/"* "$APP/Contents/Resources/Mascot/"
cp "$DESKTOP_ROOT/Info.plist" "$APP/Contents/Info.plist"
swift "$DESKTOP_ROOT/scripts/make-icon.swift" "$DESKTOP_ROOT/build/AppIcon.iconset" "$DESKTOP_ROOT/Sources/NIKADesktop/Resources/Mascot/nika_idle.png"
python3 "$DESKTOP_ROOT/scripts/pack-icon.py" "$DESKTOP_ROOT/build/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
python3 "$DESKTOP_ROOT/scripts/bundle-runtime.py" "$APP"
python3 "$DESKTOP_ROOT/scripts/bundle-webrtc.py" "$APP"
bash "$DESKTOP_ROOT/scripts/build-intents.sh" "$APP"
codesign --force --deep --sign - "$APP"
printf 'Built: %s\n' "$APP"
