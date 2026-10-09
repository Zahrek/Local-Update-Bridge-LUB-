# Local Update Bridge 1.6.8 — Developer Detection, Dynamic Type, Live Logo

- Detects full Xcode and `xcodebuild`, displays toolchain availability and offers Recheck Xcode. Disables build and DMG actions when unavailable; scanning and local update review remain available.
- Command + Plus / Minus adjusts app text scale; Command + 0 resets. Zoom persists between launches. Supported scale is 75%–180%.
- Liquid glass header mark rotates during update application, Xcode builds, DMG creation and self-update handoff. Passive scanning does not trigger spin. Existing one-off completion pulse is preserved.
- Version metadata aligned to 1.6.8.

## Limitations

This release has not been compiled/tested on macOS in the packaging environment. Test in Xcode before distribution. The CLI and SwiftUI GUI are not yet implemented atop one shared update engine, and a local source self-update still needs Xcode to compile the new app. A signed public DMG distribution requires Apple Developer signing and notarization.
