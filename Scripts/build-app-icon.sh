#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
SOURCE_PATH="$ROOT_DIR/Assets/AppIconSource.png"
DIST_DIR="$ROOT_DIR/dist/icon-build"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
BASE_PNG_PATH="$DIST_DIR/AppIcon-1024.png"
ICNS_PATH="$ROOT_DIR/Assets/AppIcon.icns"
PREVIEW_PATH="$ROOT_DIR/dist/AppIcon-preview.png"

mkdir -p "$DIST_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

cp "$SOURCE_PATH" "$BASE_PNG_PATH"
cp "$BASE_PNG_PATH" "$PREVIEW_PATH"

sips -z 16 16 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG_PATH" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$BASE_PNG_PATH" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Preview: $PREVIEW_PATH"
echo "Icon: $ICNS_PATH"
