#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$DIR/build/MiniDict.app"
BUILD_DIR="$DIR/build"
BIN_ARM64="$BUILD_DIR/MiniDict-arm64"
BIN_X86_64="$BUILD_DIR/MiniDict-x86_64"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 分别编译 Apple Silicon (arm64) 与 Intel (x86_64) 两个版本
compile_for() {
  local target="$1"
  local output="$2"
  swiftc -O -target "$target" -sdk "$SDK" \
    -framework AppKit -framework Carbon -framework CoreGraphics \
    -framework Vision -framework Foundation -lsqlite3 \
    "$DIR"/Sources/*.swift \
    -o "$output"
}

compile_for arm64-apple-macos15.0 "$BIN_ARM64"
compile_for x86_64-apple-macos15.0 "$BIN_X86_64"

# 合并为 Universal 二进制
lipo -create "$BIN_ARM64" "$BIN_X86_64" -output "$APP/Contents/MacOS/MiniDict"
rm -f "$BIN_ARM64" "$BIN_X86_64"

cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/Resources/dict.sqlite" "$APP/Contents/Resources/"
cp "$DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/"

KC="$HOME/Library/Keychains/MiniDict.keychain"
if security unlock-keychain -p minidict "$KC" 2>/dev/null; then
    security list-keychains -d user -s "$KC" "$HOME/Library/Keychains/login.keychain" 2>/dev/null || true
    codesign --force --sign "MiniDict Local Signing" --keychain "$KC" "$APP" 2>/dev/null \
      || codesign --force --sign - "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "✅ 构建完成: $APP"
file "$APP/Contents/MacOS/MiniDict"
ls -lh "$APP/Contents/MacOS/MiniDict" "$APP/Contents/Resources/dict.sqlite"
