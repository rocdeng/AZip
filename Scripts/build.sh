#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 默认构建 Release；需要调试版时：./Scripts/build.sh Debug
CONFIG="${1:-Release}"

# 版本号：每次构建把 patch 位 +1，写回 version.txt 后传给 xcodebuild。
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
    -derivedDataPath build \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build -quiet

APP="build/Build/Products/$CONFIG/AZip.app"
DEST="/Applications/AZip.app"

if [ ! -d "$APP" ]; then
    echo "构建产物不存在：$APP" >&2
    exit 1
fi

# 先结束正在运行的旧版本，避免继续用旧二进制。
pkill -f "/Applications/AZip.app/Contents/MacOS/AZip" 2>/dev/null || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# 覆盖安装：在旧版本上直接合并覆盖，不再往废纸篓堆积副本。
if [ -d "$DEST" ]; then
    [ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
fi

ditto "$APP" "$DEST"

# build 目录与 DerivedData 里的产物不参与「打开方式」，只保留 /Applications 的正式版。
if [ -x "$LSREGISTER" ]; then
    for candidate in \
        "build/Build/Products/Debug/AZip.app" \
        "build/Build/Products/Release/AZip.app" \
        "$HOME"/Library/Developer/Xcode/DerivedData/AZip-*/Build/Products/*/AZip.app; do
        [ -d "$candidate" ] && "$LSREGISTER" -u "$candidate" >/dev/null 2>&1 || true
    done
    "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

echo "AZip $VERSION ($BUILD_NUMBER, $CONFIG) → $DEST"
