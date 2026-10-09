# v1.6.9.6 — Folder permission loop correction

- Background auto-scan checks only `~/Library/Application Support/Local Update Bridge/Inbox` and explicitly approved watch folders. It no longer crawls Downloads, Desktop, Documents or `/private/var/folders` automatically.
- Import ZIP button copies a user-picked archive into the dedicated inbox, then scans the inbox.
- Folder selections save security-scoped bookmarks where supported, restored on app startup.
- Previously configured folder paths without valid bookmarks require a one-time re-selection.
- Project root is scanned only after explicit folder authorization; this prevents repeated protected-folder prompts.
- Success notice overlay suppressed; green status and icon feedback remain.

## First run

Choose Projects Folder and select your normal projects directory once. If you want Downloads watched, add Downloads explicitly as a scan location; alternatively use Import ZIP for individual updates.
