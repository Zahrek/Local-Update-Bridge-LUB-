#!/bin/bash
# This DMG deliberately includes only the compiled application and an Applications shortcut.
set -euo pipefail
APP="${1:?Usage: create-dmg.sh /path/to/App.app [output.dmg]}"
[[ -d "$APP/Contents" ]] || { echo "Not an app bundle: $APP" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-$ROOT/releases/Local-Update-Bridge.dmg}"
mkdir -p "$(dirname "$OUT")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname 'Local Update Bridge' -srcfolder "$STAGE" -ov -format UDZO "$OUT"
[[ -s "$OUT" ]] || { echo 'ERROR: DMG missing or empty.' >&2; exit 1; }
echo "DMG: $OUT"
