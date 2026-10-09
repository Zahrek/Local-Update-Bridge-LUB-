# LUB v1.6.9.12 — Visible version history and legacy receipts

Previous packages could disappear before being labeled, because Latest only was on by default. History is now shown by default, and the toggle explicitly says Hide old versions.

Receipts now load from both the current Application Support store and the legacy Update Bridge/Backups folder within the approved project root. Version maxima are preserved by logical project name, so moving a project or matching it late will not make older ZIPs appear new.

Old Version rows are grey. Roll Back is enabled ONLY if a backup of the immediately preceding installation exists; otherwise it reads Backup Unavailable. Discovery of a ZIP alone is not evidence of installation, and no app is downgraded silently.

Import the older ZIPs or add their location as an approved watch folder to see them. Native macOS compilation/rollback still require testing on your machine.