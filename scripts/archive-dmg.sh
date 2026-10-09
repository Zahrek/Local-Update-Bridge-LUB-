#!/bin/bash
# Standard Xcode archive + package. Use this for a repeatable CI/local archive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/releases/Local-Update-Bridge.xcarchive"
mkdir -p "$ROOT/releases"
xcodebuild -project "$ROOT/LocalUpdateBridge.xcodeproj" -scheme 'Local Update Bridge' -configuration Release -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive
APP="$ARCHIVE/Products/Applications/Local Update Bridge.app"
"$ROOT/scripts/package-xcode-build.sh" "$APP"
echo "Archive: $ARCHIVE"
