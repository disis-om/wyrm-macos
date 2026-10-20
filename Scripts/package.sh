#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Wyrm.app
mkdir -p dist
python3 Scripts/verify-bundle.py
lipo "$APP/Contents/MacOS/Wyrm" -verify_arch x86_64 arm64
lipo "$APP/Contents/Frameworks/SDL3.framework/SDL3" -verify_arch x86_64 arm64
otool -L "$APP/Contents/MacOS/Wyrm" | tee dist/dependencies.txt
if grep -E '/Users/|/opt/homebrew|/usr/local|libjvm' dist/dependencies.txt; then
  echo 'Non-bundled dependency detected' >&2; exit 1
fi
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/SDL3.framework"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Wyrm-macOS-universal.zip
shasum -a 256 dist/Wyrm-macOS-universal.zip > dist/SHA256SUMS
