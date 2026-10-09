# LUB v1.6.9.2 — Self-project discovery and DMG

- Project scanner no longer excludes Update Bridge.
- Detects Xcode projects at the scan root as well as direct subfolders.
- Includes the standard local LUB source checkout when the selected projects root differs.
- Shows Convert to DMG adjacent to Open in Xcode.
- Uses the correct `Local Update Bridge` Xcode scheme for LUB by default.
- DMG output is saved under the selected project’s `releases` directory.

Requires a working full Xcode installation and a native macOS Release build. Not compiled in this Linux environment.
