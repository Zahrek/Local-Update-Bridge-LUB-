# v1.6.5 — macOS binary distribution packaging

- Built on the v1.6.4 self-update history status changes.
- Added a cleaner release script with versioned, binary-only DMG output.
- Validates the built app bundle executable and code signature before packaging.
- Supports optional Developer ID signing and notarization/stapling using keychain credentials.
- Added plain-language DMG installation and GitHub Releases instructions.
- Default local releases remain ad-hoc signed and **not notarized** until maintainer credentials are configured.
- Does not alter the app's financial/project update payloads or recorded backups.
