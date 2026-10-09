# LUB v1.6.9.11 — Accurate Old Version Labels

## Why this release exists
An old, already-applied update could incorrectly display **New Version Available**. Discovery of a ZIP is not proof that it is newer than the version currently installed.

## New behavior
- **Old Version**: any package with a reliably known newer version (installed, seen, or found among other candidate ZIPs); displayed muted/grey.
- **Installed**: an update whose version matches the latest completed installation receipt for the project and whose files match the package.
- **Modified Build**: latest receipt matches but target files differ from the package.
- **Available**: discovered file with no reliable installed baseline; never misleadingly promoted to **New Version Available**.
- **New Version Available**: ONLY a package newer than the latest recorded active installation.
- **Current Version**: LUB self-update ZIP matching the running LUB version.
- Older previously applied updates remain in view in **Latest only** mode, greyed out, for historical awareness.

## Rollback safety
- **Roll Back…** is available only for the **immediately preceding** successfully applied project version, and only when the newest update has a valid rollback snapshot.
- The restoration reverses **files changed by the most recent installation**, not the entire project, and requires confirmation.
- Older packages without a verified preceding backup show **Backup Unavailable** and cannot be silently reinstalled/downgraded.
- Unmatched project updates remain discoverable but must be linked to a project before installation.

## Version comparison
- Uses manifest versions and recorded installs; not ZIP file size or Finder modification dates.
- Remembers highest observed version per project destination so removing a newer ZIP does not suddenly make old packages look like a new release.
- Uses Xcode `MARKETING_VERSION` only as supplementary evidence that a package is older; it never calls a package new based solely on that field.

## Testing
- `python3 -m unittest discover -s tests -v` exercises the eight existing CLI tests and a native-Swift version-policy test covering ten cases.
- `swiftc -frontend -parse LocalUpdateBridge.swift` checks syntax but is **not** a macOS SwiftUI build.
- Verify the full Xcode build and actual previous-version rollback on your Mac before relying on it for important projects.