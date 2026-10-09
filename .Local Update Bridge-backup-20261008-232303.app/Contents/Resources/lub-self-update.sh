#!/bin/bash
# LUB external updater. Called only after explicit in-app confirmation.
set -euo pipefail
[[ $# -eq 3 || $# -eq 4 ]] || exit 64
TARGET="$1"; SOURCE="$2"; PARENT_PID="$3"; ORIGINAL="${4:-$1}"
[[ -d "$ORIGINAL" && -d "$SOURCE" && "$TARGET" != "$SOURCE" ]] || exit 65
[[ "$TARGET" == *.app && "$SOURCE" == *.app ]] || exit 65
[[ ! -L "$TARGET" && ! -L "$SOURCE" ]] || exit 65
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist" | grep -qx 'org.lub.LocalUpdateBridge'
[[ -x "$SOURCE/Contents/MacOS/LocalUpdateBridge" ]]
DEST_DIR="$(dirname "$TARGET")"
[[ -d "$DEST_DIR" && -w "$DEST_DIR" ]] || { echo 'App destination directory must exist and be writable.' >&2; exit 73; }
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST_DIR/.Local Update Bridge-backup-$STAMP.app"
TEMP="$DEST_DIR/.Local Update Bridge-staging-$STAMP.app"
# Never touch the installed bundle before staging and verifying the replacement.
/usr/bin/ditto "$SOURCE" "$TEMP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TEMP/Contents/Info.plist" | grep -qx 'org.lub.LocalUpdateBridge'
[[ -x "$TEMP/Contents/MacOS/LocalUpdateBridge" ]]
# Give the application time to quit. Never forcibly kill it.
for i in {1..60}; do
    kill -0 "$PARENT_PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$PARENT_PID" 2>/dev/null; then
    echo 'LUB did not quit; leaving installed app untouched.' >&2
    rm -rf -- "$TEMP"
    exit 75
fi
if [[ -e "$TARGET" ]]; then
    [[ -d "$TARGET" && ! -L "$TARGET" ]] || exit 65
    mv -- "$TARGET" "$BACKUP"
else
    # A first install to the permanent folder: keep the running app as fallback.
    /usr/bin/ditto "$ORIGINAL" "$BACKUP"
fi
if ! mv -- "$TEMP" "$TARGET"; then
    mv -- "$BACKUP" "$TARGET"
    exit 1
fi
if [[ ! -x "$TARGET/Contents/MacOS/LocalUpdateBridge" ]]; then
    rm -rf -- "$TARGET"
    mv -- "$BACKUP" "$TARGET"
    exit 1
fi
# Launch by absolute bundle path; retry transient Launch Services errors.
# Verify a process carrying the updated executable is alive, rather than trusting
# the exit status of `open` alone. Preserve logs outside the app bundle.
LOG_DIR="$HOME/Library/Logs/Local Update Bridge"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/relaunch-$(date +%Y%m%d-%H%M%S).log"
exec >>"$LOG" 2>&1
printf 'Installing app: %s\n' "$TARGET"
launched=0
for attempt in 1 2 3 4 5; do
    echo "Launch attempt $attempt at $(date)"
    /usr/bin/open -n "$TARGET" || true
    sleep 3
    # pgrep -f matches the real executable path; avoid old DerivedData copies.
    if /usr/bin/pgrep -f "${TARGET}/Contents/MacOS/LocalUpdateBridge" >/dev/null 2>&1; then
        launched=1
        break
    fi
done
if [[ "$launched" -ne 1 ]]; then
    echo 'Replacement failed to relaunch; restoring prior bundle.' >&2
    /bin/mv -- "$TARGET" "${TEMP}.failed" || true
    if /bin/mv -- "$BACKUP" "$TARGET"; then
        /usr/bin/open -n "$TARGET" || true
        echo "Previous version restored. Inspect: $LOG" >&2
    else
        echo "CRITICAL: restore failed; previous app still at: $BACKUP" >&2
    fi
    exit 1
fi
# Staging is moved into its final location, and failed launch artifacts are removed.
# Keep the backup for explicit rollback; never delete the user's source ZIP.
[[ ! -e "${TEMP}.failed" ]] || echo "Failed app retained for diagnostics: ${TEMP}.failed"
# If the previous running app was a downloaded temporary copy, remove only that
# verified old .app bundle after the permanent replacement has launched.
if [[ "$ORIGINAL" != "$TARGET" && "$ORIGINAL" == "$HOME/Downloads/"* && "$ORIGINAL" == *.app && -d "$ORIGINAL" && ! -L "$ORIGINAL" ]]; then
    if /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ORIGINAL/Contents/Info.plist" 2>/dev/null | grep -qx 'org.lub.LocalUpdateBridge'; then
        /bin/rm -rf -- "$ORIGINAL" || echo "Could not clean old Downloads app: $ORIGINAL" >&2
    fi
fi
echo "Self-update installed and relaunched at: $TARGET; previous version retained at: $BACKUP"
