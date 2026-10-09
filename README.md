# Local Update Bridge (LUB)

LUB is a local-first bridge for reviewing AI-generated project update packages, applying verified payloads, and retaining recovery snapshots. This is an incremental source upgrade of the existing SwiftUI macOS bridge, including original project behavior, branded icon assets, and an **experimental** portable Python CLI. It does not contain a prebuilt or signed macOS app.

## What is included

- `LocalUpdateBridge.swift` — enhanced SwiftUI source (not compiled in this package).
- `cli/lub` — Python 3.9+ standard-library-only experimental CLI.
- `protocol/README.md` — existing v1 manifest contract and planned extensions.
- `examples/` — example package template.

## CLI examples

```sh
python3 cli/lub validate /path/to/update-folder --project '/path/to/MyProject' --json
python3 cli/lub preview /path/to/update.zip --project '/path/to/MyProject'
python3 cli/lub apply /path/to/update.zip --project '/path/to/MyProject' --approve
python3 cli/lub history --project '/path/to/MyProject'
python3 cli/lub rollback --project '/path/to/MyProject' --approve
python3 cli/lub build --project '/path/to/MyProject' --exec /usr/bin/xcrun xcodebuild -version
python3 cli/lub diagnose /path/to/build.log
```

Do not use the experimental CLI on irreplaceable projects without independent backups. The CLI and SwiftUI app **do not yet use a shared engine**; unification is the next integration milestone. A macOS Swift build and UI test are still required before substituting the compiled `.app`. The current GUI still implements its original update engine.

## Security and compatibility

- Explicit approval required for CLI mutations; no automatic patch execution.
- Manifest is verified, SHA-256 checked, and paths are normalized before file writes.
- Snapshots are outside the project, under `~/.local/share/lub/backups`.
- CLI v1 currently handles file creation/replacement, not deletion, dependency installation, or config migration.
- Build/test commands are executed only when explicitly provided and are **not taken from untrusted manifest content**.
- ZIP packages containing symlink entries are rejected; extra hardening is required before unattended production automation.

## Next milestones

Unify GUI and CLI behind one authoritative engine; add atomically journaled apply and rollback, persistent project profiles, full build adapters and richer diagnostics, package signing/trust policies, proper semantic history filtering, UI animations/toasts, tests and CI, documentation and licensing. MIT is proposed, but an authorized rights holder should add the final license and copyright attribution.

## Build on your Mac (new logo included)

```bash
cd "Update Bridge"
./build-macos.sh
open "dist/Local Update Bridge.app"
```

The build generates a real macOS `LUBIcon.icns` from `branding/LUBIcon.iconset`, includes `LUBIcon.png` for the dashboard and embeds the CLI. The source ZIP includes the editable SVG and the full iconset. **Keep your currently working app and backups until the new build is verified.**

### Implemented in this revision
- Original source retained and updated (not an Xcode project).
- Actual dual-arrow application icon assets and in-window branded graphic, with spin while working.
- GUI rollback metadata now records created versus replaced files; newly created files are removed on rollback; rollback validates paths and backup existence.
- Incremental per-file apply progress.

### Not yet complete
- GUI and CLI still have independent update implementations.
- True atomic, durable cross-process rollback/recovery; malicious ZIP hardening in Swift GUI; universal non-Xcode project discovery in GUI.
- Full green/red/orange bounce/flash sequences, reliable stage-based toasts, async/byte-accurate build progress, project-profile persistence, manifest-driven delete/config/dependency operations.
- macOS compilation, code signing and notarization require a Mac.

### CLI regression tests (vNext.2)

```bash
python3 -m unittest discover -s tests -v
```

The CLI uses only Python standard-library dependencies. Its `--version` reports the CLI version independently of the macOS GUI. Preserve the original installed application until a macOS build of this source succeeds. The GUI still uses its existing Swift update implementation; CLI safety tests do not yet certify the GUI installation path.

### vNext.3: Folder meanings and auto-discovery

**Projects location** is the parent directory containing existing Xcode projects. Reviewed updates are applied to the matching project *within this directory*, never into the update storage folder. **Update storage destination** is the directory where LUB creates its `Update Bridge` staging, backups and logs. By default, storage resides beneath the projects location for compatibility with existing installations. Choose a separate storage location for cleaner separation.

LUB automatically rescans approximately every 12 seconds when idle. Default scan locations include Downloads, Desktop, Documents and Codex temporary preview locations. Add further directories with **Add Scan Location**. Only archives/directories with a valid recognized `bridge-manifest.json` are listed; placing an arbitrary ZIP in Downloads does not make it an applicable update. The list defaults to latest-version-only, newest modified file first. Approval is still mandatory before application.

**Build note:** `build-macos.sh` uses `swiftc -parse-as-library`. This source package has not been compiled in macOS by the packaging environment; build and test locally before replacing an installed app.
