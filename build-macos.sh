#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v swiftc >/dev/null || { echo "Install Xcode Command Line Tools" >&2; exit 1; }
command -v iconutil >/dev/null || { echo "iconutil is required on macOS" >&2; exit 1; }
APP="dist/Local Update Bridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -O -framework SwiftUI -framework AppKit -framework CryptoKit -framework UserNotifications LocalUpdateBridge.swift -o "$APP/Contents/MacOS/LocalUpdateBridge"
cp branding/LUBIcon.png "$APP/Contents/Resources/LUBIcon.png"
cp branding/LUBMark.png "$APP/Contents/Resources/LUBMark.png"
iconutil -c icns branding/LUBIcon.iconset -o "$APP/Contents/Resources/LUBIcon.icns"
cp cli/lub "$APP/Contents/Resources/lub"
cp lub-self-update.sh "$APP/Contents/Resources/lub-self-update.sh"
cp lub-source-update.sh "$APP/Contents/Resources/lub-source-update.sh"
chmod +x "$APP/Contents/Resources/lub-self-update.sh"
chmod +x "$APP/Contents/Resources/lub-source-update.sh"
chmod +x "$APP/Contents/Resources/lub"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalUpdateBridge</string>
<key>CFBundleIdentifier</key><string>org.lub.LocalUpdateBridge</string>
<key>CFBundleName</key><string>Local Update Bridge</string>
<key>CFBundleDisplayName</key><string>Local Update Bridge</string>
<key>CFBundleIconFile</key><string>LUBIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.9.7</string>
<key>CFBundleVersion</key><string>1697</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "Built $APP (unsigned). Test before replacing your installed app."
