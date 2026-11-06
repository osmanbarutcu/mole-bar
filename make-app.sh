#!/bin/bash
# MoleBar.app paketini üretir (SwiftPM release + Info.plist + ad-hoc imza).
set -euo pipefail

cd "$(dirname "$0")"
APP="MoleBar.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MoleBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MoleBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MoleBar</string>
    <key>CFBundleIdentifier</key><string>local.molebar</string>
    <key>CFBundleName</key><string>MoleBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Hazır: $(pwd)/$APP"
