#!/bin/bash
set -euo pipefail

OUT="${1:-/tmp/AZipTest.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/TestApp.app/Contents/MacOS"
cat > "$STAGE/TestApp.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>TestApp</string>
	<key>CFBundleIdentifier</key>
	<string>com.dengpeng.AZip.TestApp</string>
	<key>CFBundleName</key>
	<string>TestApp</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

printf '#!/bin/sh\necho AZip test app\n' > "$STAGE/TestApp.app/Contents/MacOS/TestApp"
chmod +x "$STAGE/TestApp.app/Contents/MacOS/TestApp"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
printf '\x89PNG\r\n\x1a\n' > "$STAGE/.background/background.png"

hdiutil create -volname "AZipTest" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "created: $OUT"
