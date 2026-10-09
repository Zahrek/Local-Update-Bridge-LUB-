# LUB Xcode / GitHub publication

## Open and test
1. Open `LocalUpdateBridge.xcodeproj` with recent Xcode on macOS 14+.
2. Select scheme **Local Update Bridge** and **My Mac**.
3. Press Cmd+B then Cmd+R. The first run can require approving permissions for watched folders.
4. Run `python3 -m unittest discover -s tests -v` to check the bundled CLI.

## Local DMG
`./scripts/release.sh` builds Release and writes `releases/Local-Update-Bridge.dmg`.
It uses ad-hoc signing unless `LUB_SIGN_IDENTITY` is supplied.

## Developer ID public release
1. Obtain Apple Developer Program membership and a Developer ID Application certificate.
2. Run `LUB_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh`.
3. Notarize the DMG with `xcrun notarytool submit releases/Local-Update-Bridge.dmg --keychain-profile YOUR_PROFILE --wait`.
4. `xcrun stapler staple releases/Local-Update-Bridge.dmg` and `xcrun stapler validate releases/Local-Update-Bridge.dmg`.
5. Upload to GitHub Releases, ideally alongside a SHA-256 checksum.

**Important:** this application scans folders, runs builds, and installs project updates. Sandbox is disabled for those workflows. Only run trusted update packages. The existing self-update shell installer is not a notarized, signature-verified updater and must not be used as the automatic public release mechanism. Plan a signed update feed with version + signature checking before enabling unattended production updates.

## GitHub
Create a new GitHub repository, then from the project directory:
```
git init
git add .
git commit -m "Initial Xcode macOS app packaging"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/local-update-bridge.git
git push -u origin main
```
Replace the placeholder URL with your repository URL. Use Xcode > Product > Archive for a manual distribution workflow.
