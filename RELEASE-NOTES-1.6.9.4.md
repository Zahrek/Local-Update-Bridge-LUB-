# Local Update Bridge v1.6.9.4

- Stabilized update-row layout (fixed progress space, narrow completion status, reserved action columns).
- Project DMG creation now opens a macOS Save dialog and saves exactly where selected.
- Source self-updates target `~/Documents/App projects/Update Bridge/Local Update Bridge.app`, not the downloaded source folder.
- External helper stages, backs up, replaces, retries launch, and restores on failure.
- Replaced app bundles are moved into a versioned backup for rollback. Source ZIP files are preserved.
- On successful launch, temporary staged app files are cleaned up automatically.

**Requires a one-time install of this version through Xcode** for these updater changes to take effect.
Native SwiftUI compilation and real macOS relaunch/DMG tests remain necessary.
