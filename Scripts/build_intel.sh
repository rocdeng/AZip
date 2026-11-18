#!/bin/bash
# 构建 Intel (x86_64) 版本。
#
# - 在 Intel Mac 上：原生构建，直接可用
# - 在 Apple Silicon 上：交叉编译，产物只能拿到 Intel 机器上运行
#
# 与 build.sh 的区别只在架构与 derivedData 目录（互不覆盖）。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"

VERSION_FILE="version.txt"
[ -f "$VERSION_FILE" ] || printf '0.1.0\n' > "$VERSION_FILE"

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
MAJOR="${CURRENT%%.*}"
REST="${CURRENT#*.}"
MINOR="${REST%%.*}"
PATCH="${REST##*.}"
PATCH=$((PATCH + 1))
VERSION="$MAJOR.$MINOR.$PATCH"
printf '%s\n' "$VERSION" > "$VERSION_FILE"

BUILD_NUMBER="$(date +%Y%m%d%H%M)"

xcodegen generate
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration "$CONFIG" \
    -derivedDataPath build-intel \
    ARCHS=x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build -quiet

APP="build-intel/Build/Products/$CONFIG/AZip.app"
DEST="/Applications/AZip.app"

if [ ! -d "$APP" ]; then
    echo "构建产物不存在：$APP" >&2
    exit 1
fi

BINARY_ARCH="$(lipo -archs "$APP/Contents/MacOS/AZip" 2>/dev/null || echo unknown)"
echo "构建架构：$BINARY_ARCH"
if [[ "$BINARY_ARCH" != *"x86_64"* ]]; then
    echo "警告：产物不是 x86_64（当前：$BINARY_ARCH）" >&2
fi

pkill -f "/Applications/AZip.app/Contents/MacOS/AZip" 2>/dev/null || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ -d "$DEST" ]; then
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
fi

ditto "$APP" "$DEST"

if [ -x "$LSREGISTER" ]; then
    for candidate in \
        "build-intel/Build/Products/Debug/AZip.app" \
        "build-intel/Build/Products/Release/AZip.app"; do
        [ -d "$candidate" ] && "$LSREGISTER" -u "$candidate" >/dev/null 2>&1 || true
    done
    "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

echo "AZip $VERSION ($BUILD_NUMBER, $CONFIG, x86_64) → $DEST"
