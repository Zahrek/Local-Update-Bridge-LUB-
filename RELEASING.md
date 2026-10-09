# Local Update Bridge — release workflows

## 1. Xcode Archive / Distribute App
Open `LocalUpdateBridge.xcodeproj`, choose **Local Update Bridge** and **My Mac**. Choose **Product > Archive**. The Organizer opens and offers **Distribute App**. Export the app with appropriate signing. To create a DMG from an exported app, use `scripts/package-xcode-build.sh "/path/to/Local Update Bridge.app"` from Terminal; alternatively run `scripts/archive-dmg.sh` to archive and package in one operation. A DMG is a separate package format, not an Xcode Organizer export option.

## 2. Xcode DMG scheme
Select **Local Update Bridge — DMG** (shared scheme) and **My Mac**, then **Product > Build** (Command-B). The scheme builds in Release and its post-build action packages the resulting app as `releases/Local-Update-Bridge-vVERSION.dmg` plus SHA-256. The normal scheme is unchanged. The post-action uses Xcode's built-product environment; if the app is missing, the action fails rather than packaging an older app.

## 3. GitHub Actions
Push to `main` to build and upload an unsigned/ad-hoc signed testing DMG as a workflow artifact (not a GitHub Release). Push an annotated version tag, e.g. `v1.6.5`, to trigger a Developer ID signed, notarized DMG build and a GitHub Release. It **will fail closed** if signing secrets are missing. In repository Settings > Secrets and variables > Actions configure: `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `MACOS_DEVELOPER_ID_IDENTITY`, `APPLE_TEAM_ID`, `APPLE_NOTARY_APPLE_ID`, `APPLE_NOTARY_APP_PASSWORD`. The P12 must contain the Developer ID Application signing identity. Use a dedicated Apple ID app-specific password for notarization. Restrict who may push release tags. Never commit certificates or passwords.

### Public distribution
A GitHub tag release must use Developer ID signing and notarization. Run `spctl --assess --type execute -vv /path/to/Local\ Update\ Bridge.app` and `xcrun stapler validate /path/to/file.dmg` on macOS before distributing widely. Local unsigned DMGs are for testing only.

### Version management
Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project before tagging. `scripts/release.sh` names output from the compiled app's `CFBundleShortVersionString`.

### Limitations
macOS builds, Xcode Organizer operations, signing and notarization require a Mac/Xcode installation and credentials; they cannot be validated on Linux. The source-based self-updater is not an appropriate updater for notarized public releases; signed-release updates need their own verification and installation path.

## Exporting a selected project directly from LUB (new)

Choose a project in LUB's **Project** selector, set **Optional build scheme** to that
project's macOS application scheme (if it differs from its `.xcodeproj` name), then
click **Create DMG**. LUB runs `xcodebuild` with the **Release** configuration and
`generic/platform=macOS`, packages the resulting single `.app` bundle, and saves
`<Project Folder>/releases/<App Name>-v<Version>.dmg`. The folder opens automatically.

This function supports macOS application schemes only; it intentionally fails for
iOS-only schemes, schemes producing no app, or schemes producing multiple apps.
It requires Xcode and its command-line tools on the Mac. Logs are saved under
LUB's Application Support `Logs` folder. The DMG is a local/testing package:
public Gatekeeper-friendly distribution requires Developer ID signing and notarization.
