# LUB v1.6.9.7 — Update discovery recovery

- Imported updates remain discoverable in the Application Support/LUB Inbox even after denial of broad access to Downloads or Documents.
- Added an **Open LUB Inbox** action so users can drop a ZIP there directly.
- Explicit **Import ZIP** now briefly retains security-scoped access during the copy and releases it afterwards.
- Project discovery no longer requires a stored bookmark when the selected folder is already readable (unsandboxed builds).
- If the selected Projects folder is unavailable, the interface explains how to re-select it, without disabling update scanning.
- Synced Xcode, source-builder and self-update metadata version to 1.6.9.7.

**Privacy:** This release does not bypass macOS permissions. If access to a protected folder is denied, reauthorize that folder with its picker, use Import ZIP, or place a ZIP in the LUB Inbox.
