#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$DIR/build/MiniDict.app"
BUILD_DIR="$DIR/build"
BIN_ARM64="$BUILD_DIR/MiniDict-arm64"
BIN_X86_64="$BUILD_DIR/MiniDict-x86_64"

mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 读取本地 .env 配置（如果存在）
ENV_FILE="$DIR/.env"
ENV_SWIFT="$BUILD_DIR/EnvConfig.swift"

OPENAI_API_KEY=""
OPENAI_URL=""
OPENAI_MODEL=""
DEFAULT_ENGINE=""
YOUDAO_APP_KEY=""
YOUDAO_APP_SECRET=""

if [ -f "$ENV_FILE" ]; then
  echo "🔍 检测到本地 .env 配置文件，正在读取环境配置..."
  while IFS='=' read -r key val || [ -n "$key" ]; do
    key="$(echo "$key" | tr -d '[:space:]')"
    [[ "$key" =~ ^#.*$ ]] && continue
    [ -z "$key" ] && continue
    val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    case "$key" in
      OPENAI_API_KEY) OPENAI_API_KEY="$val" ;;
      OPENAI_URL) OPENAI_URL="$val" ;;
      OPENAI_MODEL) OPENAI_MODEL="$val" ;;
      DEFAULT_ENGINE) DEFAULT_ENGINE="$val" ;;
      YOUDAO_APP_KEY) YOUDAO_APP_KEY="$val" ;;
      YOUDAO_APP_SECRET) YOUDAO_APP_SECRET="$val" ;;
    esac
  done < "$ENV_FILE"
else
  echo "ℹ️ 未检测到 .env 配置文件，使用纯净开源默认配置构建..."
fi

# 生成仅在编译时使用的 EnvConfig.swift
cat <<EOF > "$ENV_SWIFT"
import Foundation

struct EnvConfig {
    static let openAIApiKey = "$OPENAI_API_KEY"
    static let openAIUrl = "$OPENAI_URL"
    static let openAIModel = "$OPENAI_MODEL"
    static let defaultEngine = "$DEFAULT_ENGINE"
    static let youdaoAppKey = "$YOUDAO_APP_KEY"
    static let youdaoAppSecret = "$YOUDAO_APP_SECRET"
}
EOF

# 分别编译 Apple Silicon (arm64) 与 Intel (x86_64) 两个版本
compile_for() {
  local target="$1"
  local output="$2"
  swiftc -O -target "$target" -sdk "$SDK" \
    -framework AppKit -framework Carbon -framework CoreGraphics \
    -framework Vision -framework Foundation -lsqlite3 \
    "$DIR"/Sources/*.swift "$ENV_SWIFT" \
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

# 自动杀死正在运行的旧版本进程并启动新版本
echo "🔄 正在重启应用..."
killall MiniDict 2>/dev/null || true
if [ -d "/Applications/MiniDict.app" ]; then
    rm -rf /Applications/MiniDict.app
    cp -R "$APP" /Applications/
    open -a /Applications/MiniDict.app || open "$APP"
else
    open -a "$APP" || open "$APP"
fi
echo "🚀 MiniDict 已重新启动！"
