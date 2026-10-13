#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NIKA_BUILD_CONFIGURATION=debug bash "$DESKTOP_ROOT/scripts/build-app.sh"
export NIKA_DESKTOP_DATA="${NIKA_DESKTOP_DATA:-$DESKTOP_ROOT/.dev-data}"
mkdir -p "$NIKA_DESKTOP_DATA"
exec "$DESKTOP_ROOT/build/NIKA Desktop.app/Contents/MacOS/NIKADesktop"
