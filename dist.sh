#!/usr/bin/env bash
# Builds a release .app and zips it for transport to another Mac.
# Produces: dist/DragAndAsk-vX.Y.Z.zip
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Pull version from Info.plist (CFBundleShortVersionString).
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" bundle/Info.plist 2>/dev/null || echo "0.0.0")
ARCH=$(uname -m)

./build.sh

DIST_DIR="$SCRIPT_DIR/dist"
mkdir -p "$DIST_DIR"
OUT_ZIP="$DIST_DIR/DragAndAsk-v${VERSION}-${ARCH}.zip"
rm -f "$OUT_ZIP"

echo "==> creating $OUT_ZIP"
# Use ditto so extended attributes and signature are preserved (zip is unreliable for .app).
ditto -c -k --keepParent "$SCRIPT_DIR/build/DragAndAsk.app" "$OUT_ZIP"

echo ""
echo "Done."
echo "  $OUT_ZIP"
echo ""
echo "Transfer to the other Mac (AirDrop / iCloud / USB), then on that Mac:"
echo "  1. Unzip — Finder will produce DragAndAsk.app"
echo "  2. Right-click DragAndAsk.app → Open (Gatekeeper bypass for unidentified developer)"
echo "  3. Grant Accessibility & Apple Events permission when prompted"
echo "  4. Open Settings, paste your Gemini API key"
