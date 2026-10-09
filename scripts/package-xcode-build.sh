#!/bin/bash
# Executed as a Build post-action of the dedicated DMG scheme, not as a target Run Script phase.
set -euo pipefail
APP="${1:?Xcode must supply the built .app path}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -d "$APP/Contents" ]]; then
  echo "ERROR: No compiled application at $APP" >&2; exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="$ROOT/releases/Local-Update-Bridge-v${VERSION}.dmg"
"$ROOT/scripts/create-dmg.sh" "$APP" "$OUT"
shasum -a 256 "$OUT" > "$OUT.sha256"
echo "DMG created: $OUT"
