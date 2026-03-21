#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP_NAME="MacInputSourceLock"
BUNDLE_IDENTIFIER="com.macinputsourcelock.app"
VERSION_LABEL="${1:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
SHORT_VERSION=$(printf '%s' "$VERSION_LABEL" | sed -E 's/^v//; s/[^0-9.].*$//')
BUILD_VERSION=$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)
ARCH=$(uname -m)

if [[ -z "$SHORT_VERSION" ]]; then
    SHORT_VERSION="0.0.0"
fi

BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
PKGINFO_PATH="$CONTENTS_DIR/PkgInfo"
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
ICON_SOURCE_PATH="$ROOT_DIR/Assets/AppIcon.icns"
ICON_OUTPUT_PATH="$RESOURCES_DIR/AppIcon.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION_LABEL-macos-$ARCH.zip"

cd "$ROOT_DIR"
zsh "$ROOT_DIR/Scripts/build-app-icon.sh" >/dev/null
swift build -c release

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Expected release executable at $EXECUTABLE_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ICON_SOURCE_PATH" "$ICON_OUTPUT_PATH"
find "$ROOT_DIR/.build" -path "*/release/*.bundle" -exec cp -R {} "$RESOURCES_DIR/" \;

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$PKGINFO_PATH"

codesign --force --sign - "$MACOS_DIR/$APP_NAME" >/dev/null
codesign --force --deep --sign - "$APP_DIR" >/dev/null

xattr -cr "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "App bundle: $APP_DIR"
echo "Release zip: $ZIP_PATH"
