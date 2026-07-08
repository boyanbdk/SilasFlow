#!/bin/bash
# Builds SilasFlow with SPM and assembles a runnable .app bundle.
# Usage: scripts/build_app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/SilasFlow.app"

# Stable self-signed identity keeps the Accessibility grant across rebuilds.
# Falls back to ad-hoc ("-") if the identity isn't in the keychain.
SIGN_IDENTITY="${SILASFLOW_SIGN_IDENTITY:-SilasFlow Local Signing}"
if ! security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "!! Signing identity '$SIGN_IDENTITY' not found — falling back to ad-hoc"
    SIGN_IDENTITY="-"
fi

echo "==> swift build -c $CONFIG"
cd "$ROOT"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/SilasFlow"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SilasFlow"
cp "$ROOT/Resources/SilasFlow-Info.plist" "$APP/Contents/Info.plist"

echo "==> Codesigning with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

echo "==> Done: $APP"
echo "    Launch with: open \"$APP\""
