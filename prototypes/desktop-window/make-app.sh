#!/bin/zsh
# Builds the prototype and wraps it in a minimal .app bundle (so macOS treats it like a real app),
# then launches it. Usage: ./make-app.sh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/66 Days Prototype.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DesktopWindowPrototype "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.ethanlee7102.66days.prototype</string>
    <key>CFBundleName</key><string>66 Days Prototype</string>
    <key>CFBundleExecutable</key><string>DesktopWindowPrototype</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
pkill -f "66 Days Prototype.app" || true
open "$APP"
echo "Launched. Look for '66' in the menu bar. Log: ~/Library/Logs/66DaysPrototype.log"
