#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration Debug -derivedDataPath build build -quiet
