#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

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
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration Debug \
    -derivedDataPath build \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build -quiet

APP="build/Build/Products/Debug/AZip.app"
DEST="/Applications/AZip.app"

# 覆盖安装：旧版本移入废纸篓（可恢复），不直接删除。
if [ -d "$DEST" ]; then
    mkdir -p "$HOME/.Trash"
    mv "$DEST" "$HOME/.Trash/AZip-$BUILD_NUMBER.app"
fi

ditto "$APP" "$DEST"
echo "AZip $VERSION ($BUILD_NUMBER) → $DEST"
