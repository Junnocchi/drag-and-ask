#!/usr/bin/env bash
# Build drag & ask as a macOS .app bundle without Xcode.
# Produces: build/DragAndAsk.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="DragAndAsk"
BUNDLE_ID="com.draganddask.app"
CONFIG="${CONFIG:-release}"

OUT_DIR="$SCRIPT_DIR/build"
APP_DIR="$OUT_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build failed: binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$SCRIPT_DIR/bundle/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# --- App icon: convert bundle/icon.png (1024x1024) into AppIcon.icns ---
if [[ -f "$SCRIPT_DIR/bundle/icon.png" ]]; then
    echo "==> building AppIcon.icns from bundle/icon.png"
    ICON_TMP="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICON_TMP"
    SRC="$SCRIPT_DIR/bundle/icon.png"
    sips -z 16 16     "$SRC" --out "$ICON_TMP/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$SRC" --out "$ICON_TMP/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$SRC" --out "$ICON_TMP/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$SRC" --out "$ICON_TMP/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$SRC" --out "$ICON_TMP/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$SRC" --out "$ICON_TMP/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$SRC" --out "$ICON_TMP/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$SRC" --out "$ICON_TMP/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$SRC" --out "$ICON_TMP/icon_512x512.png"    >/dev/null
    cp "$SRC" "$ICON_TMP/icon_512x512@2x.png"
    iconutil -c icns -o "$RES_DIR/AppIcon.icns" "$ICON_TMP"
fi

echo "==> ad-hoc codesigning with entitlements"
codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/bundle/DragAndAsk.entitlements" \
    --options runtime \
    "$APP_DIR"

echo ""
echo "Done. Launch with:"
echo "  open $APP_DIR"
echo ""
echo "Tip: if Accessibility permission was granted previously to an older build,"
echo "remove the entry in System Settings > Privacy & Security > Accessibility"
echo "and re-add this build."
