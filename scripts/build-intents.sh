#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTENTS_OUTPUT="$DESKTOP_ROOT/build/intents"
mkdir -p "$INTENTS_OUTPUT"
printf '["AppIntent","AppShortcutsProvider","AppEntity","AppEnum"]' > "$INTENTS_OUTPUT/protocols.json"
xcrun swiftc -emit-module -module-name NIKADesktop -target arm64-apple-macosx14.0 \
  -emit-module-path "$INTENTS_OUTPUT/NIKADesktop.swiftmodule" \
  -Xfrontend -const-gather-protocols-file -Xfrontend "$INTENTS_OUTPUT/protocols.json" \
  -Xfrontend -emit-const-values-path -Xfrontend "$INTENTS_OUTPUT/shortcuts.swiftconstvalues" \
  "$DESKTOP_ROOT/Sources/NIKADesktop/DesktopShortcuts.swift"
printf '%s\n' "$DESKTOP_ROOT/Sources/NIKADesktop/DesktopShortcuts.swift" > "$INTENTS_OUTPUT/sources.txt"
printf '%s\n' "$INTENTS_OUTPUT/shortcuts.swiftconstvalues" > "$INTENTS_OUTPUT/constants.txt"
xcrun appintentsmetadataprocessor \
  --output "$1/Contents/Resources" \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name NIKADesktop --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
  --platform-family macOS --deployment-target 14.0 --target-triple arm64-apple-macosx14.0 \
  --source-file-list "$INTENTS_OUTPUT/sources.txt" --swift-const-vals-list "$INTENTS_OUTPUT/constants.txt" \
  --app-shortcuts-app-name-override
