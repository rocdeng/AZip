#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 测试产物统一放到 build/，避免污染默认 DerivedData。
# 默认 DerivedData 里的同名 app 会被 LaunchServices 抢成默认打开程序。
xcodebuild test -project AZip.xcodeproj -scheme AZip \
    -destination 'platform=macOS' \
    -derivedDataPath build \
    -quiet

# 测试会编译 Debug 版 app，跑完立刻注销，只保留 /Applications 的正式版。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    for candidate in \
        "build/Build/Products/Debug/AZip.app" \
        "build/Build/Products/Release/AZip.app" \
        "$HOME"/Library/Developer/Xcode/DerivedData/AZip-*/Build/Products/*/AZip.app; do
        [ -d "$candidate" ] && "$LSREGISTER" -u "$candidate" >/dev/null 2>&1 || true
    done
    "$LSREGISTER" -f "/Applications/AZip.app" >/dev/null 2>&1 || true
fi
