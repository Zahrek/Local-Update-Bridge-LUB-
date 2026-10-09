#!/bin/bash
# Create a binary-only, drag-to-Applications release of Local Update Bridge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v xcodebuild >/dev/null || { echo 'ERROR: Xcode is required (run on macOS).' >&2; exit 1; }
command -v hdiutil >/dev/null || { echo 'ERROR: hdiutil is required.' >&2; exit 1; }
DERIVED="$ROOT/.build/release"
mkdir -p "$ROOT/releases"
# Use LUB_SIGN_IDENTITY='Developer ID Application: ...' to make a distributable, signed build.
# By default create an ad-hoc signed build for local testing only.
IDENTITY="${LUB_SIGN_IDENTITY:--}"
BUILD_ARGS=( -project LocalUpdateBridge.xcodeproj -scheme 'Local Update Bridge'
  -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED"
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="$IDENTITY" )
if [[ "$IDENTITY" != '-' ]]; then
  BUILD_ARGS+=( CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--options=runtime" )
  if [[ -n "${LUB_TEAM_ID:-}" ]]; then BUILD_ARGS+=( DEVELOPMENT_TEAM="$LUB_TEAM_ID" ); fi
fi
xcodebuild "${BUILD_ARGS[@]}" clean build
APP="$DERIVED/Build/Products/Release/Local Update Bridge.app"
[[ -d "$APP/Contents" ]] || { echo "ERROR: Missing app bundle: $APP" >&2; exit 1; }
EXE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")
[[ -x "$APP/Contents/MacOS/$EXE" ]] || { echo "ERROR: App executable missing: $EXE" >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$IDENTITY" != '-' ]]; then
  /usr/bin/codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID Application' >/dev/null || {
    echo 'ERROR: The app is not signed with Developer ID Application.' >&2; exit 1;
  }
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$ROOT/releases/Local-Update-Bridge-v$VERSION.dmg"
"$ROOT/scripts/create-dmg.sh" "$APP" "$DMG"
if [[ -n "${LUB_NOTARY_PROFILE:-}" ]]; then
  if [[ "$IDENTITY" == '-' ]]; then echo 'ERROR: Notarization requires Developer ID signing.' >&2; exit 1; fi
  NOTARY_ARGS=(--keychain-profile "$LUB_NOTARY_PROFILE")
  if [[ -n "${LUB_NOTARY_KEYCHAIN:-}" ]]; then NOTARY_ARGS+=(--keychain "$LUB_NOTARY_KEYCHAIN"); fi
  xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo 'NOTARIZED: DMG stapled and validated.'
else
  echo 'NOT notarized. This DMG is suitable for local testing, not frictionless public distribution.'
fi
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Release: $DMG"
