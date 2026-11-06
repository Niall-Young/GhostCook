#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodegen generate
xcodebuild -project Onecook.xcodeproj -scheme Onecook -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/TestData test
