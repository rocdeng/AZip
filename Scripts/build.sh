#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project AZip.xcodeproj -scheme AZip -configuration Debug build -quiet
