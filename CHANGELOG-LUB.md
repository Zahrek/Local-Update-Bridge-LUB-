# Upgrade notes — 2026-10-08

- Inspected existing single-file macOS SwiftUI implementation and retained its current data/backup/log history.
- Added GUI source controls for sort order, latest-only filtering, project/destination picker, text scaling shortcuts, progress stages, operation notice overlay and rotating status icon.
- Added experimental protocol-compatible command-line tool with validation, preview, approved apply, snapshots, restore, history, status, build/test command execution and log diagnosis.
- Added protocol documentation and quickstart.

## Not yet complete / known limitations

- No macOS compiler in the authoring environment: updated SwiftUI source not compiled or validated in Xcode; existing packaged `.app` binary is unchanged.
- GUI and CLI are not yet backed by one shared engine.
- CLI does not currently support delete operations, trusted signing or comprehensive race-free filesystem guarantees.
- GUI destination-root preference is stored but not yet connected to an arbitrary external build/output pipeline; it must not redirect project patch application implicitly.
- GUI retains original rollback method and original on-main-thread build routine; these require improvement before making build/rollback unattended.
- Custom orange-double-flash, green/red bounce and toast auto-dismiss are not fully implemented. The source currently changes icon tint and rotation, with a dismissible status notice.
- Percentages in GUI are coarse stage indicators rather than byte-accurate injection progress.

## Follow-up source release
- Added original LUB brand SVG/PNG and macOS iconset.
- Added `build-macos.sh` to package unsigned `.app` with `.icns`, source PNG, embedded CLI and Info.plist.
- GUI now renders bundled brand mark, and per-file progress is updated during apply.
- Rollback metadata records existence of each pre-update file and removes newly created files on rollback.
- Explicitly documented remaining safety and cross-platform gaps.

## vNext.2 — CLI validation and recovery hardening

- Added regression tests covering approval, checksum validation, directory traversal, symlink escape, ZIP ingestion, creation/replacement, rollback, and build errors.
- Added maximum ZIP-entry count and total uncompressed-size limits.
- Validate SHA-256 format and manifest file count before applying.
- Reject symlinked project roots and unsafe destination parents.
- Persist rollback metadata atomically with fsync and rename.
- Refuse normal rollback of an incomplete snapshot, directing the user to manual recovery rather than guessing.
- Record actual restored snapshot path after rollback.
- Added CLI `--version` output.

**Verification:** 8 Python unittest cases pass on Linux. The macOS SwiftUI application has not been compiled or run here. GUI/CLI shared engine, fully durable recovery, and state animations remain pending.

## vNext.3 — Project/storage clarity and automatic update discovery
- Split folder configuration into **Projects location** (where reviewed updates are applied) and **Update storage destination** (staging, snapshots, and logs). Changing the storage destination now changes the actual bridge storage root rather than an unused preference.
- Added persisted auto-scan toggle (enabled by default, approximately every 12 seconds when idle).
- Scan Downloads, Desktop, Documents, Codex preview locations, plus configurable user-added scan folders.
- Inspect ZIP names generically; only packages with a supported root `bridge-manifest.json` are shown.
- Default to latest-version-only and newest-file-first sorting, with manual sorting/filter control retained.
- Show the last scan timestamp and custom watched-folder removal controls.
- Corrected build script to include `swiftc -parse-as-library` for the existing SwiftUI `@main` entry point.
- Existing protocol CLI regression tests remain passing. SwiftUI compile still requires macOS.

## vNext.5 — Destination defaults and installed state
- Update installation destination defaults to the currently selected project's folder.
- Per-project custom destination can be chosen and reset independently; the global project-discovery root is unaffected.
- Backups/staging stay under ~/Library/Application Support/Local Update Bridge/Update Bridge, separate from selected project and installation destination.
- Available updates successfully applied through the GUI display an Installed badge, are dimmed, and cannot be re-applied through the Review button until rolled back.
- Installed status is reconstructed from completed restore records on scan and cleared after successful rollback. This is version/target history, not a live comparison against changed files; any external edits are not tracked.
- Existing CLI regression suite remains intact.
