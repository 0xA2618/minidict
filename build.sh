#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$DIR/build/MiniDict.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -target arm64-apple-macos15.0 -sdk "$SDK" \
  -framework AppKit -framework Carbon -framework CoreGraphics \
  -framework Vision -framework Foundation -lsqlite3 \
  "$DIR"/Sources/*.swift \
  -o "$APP/Contents/MacOS/MiniDict"

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
ls -lh "$APP/Contents/MacOS/MiniDict" "$APP/Contents/Resources/dict.sqlite"
