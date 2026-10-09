# Local Update Bridge — Xcode macOS app

This folder includes a native Xcode project wrapping the **existing SwiftUI source** and LUB CLI. Open `LocalUpdateBridge.xcodeproj` and run the **Local Update Bridge** scheme on **My Mac**.

- `LocalUpdateBridge.swift` — existing app code, not rewritten
- `Assets.xcassets` — macOS Dock icon in asset catalog
- `branding/LUBMark.png` — transparent animated header mark
- `cli/lub`, `lub-*.sh` — bundled helpers copied to `Contents/Resources`
- `scripts/release.sh` — builds the Release app and a drag-to-Applications DMG
- `GITHUB-RELEASE.md` — GitHub, signing, notarization instructions

**Current limitations:** The Xcode project and release scripts were generated outside macOS and could not be built with `xcodebuild` here. Confirm a local Mac build before publishing. Future signed releases should use a verified signed update mechanism; the existing source ZIP updater is not a secure substitute.

GitHub Actions builds an unsigned testing DMG on each push to main; signed public releases require your own Developer ID credentials and notarization.
