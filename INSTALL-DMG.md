# Installing Local Update Bridge (no source code required)

1. Download the **notarized** `Local-Update-Bridge-vX.Y.Z.dmg` from the project's official GitHub Releases page.
2. Double-click the DMG to mount it.
3. Drag **Local Update Bridge.app** onto the **Applications** folder shortcut.
4. Eject the mounted disk image; launch the app from Applications.
5. To upgrade, download the newer official DMG and replace the previous app in Applications (quit LUB first). The app's preferences and user data in Application Support remain separate from the application bundle.

**Security:** For public distribution the maintainer must sign with Apple Developer ID, notarize and staple the DMG. Do not tell users to bypass Gatekeeper. An unsigned/unnotarized test DMG may be blocked on other Macs.

**No developer tools or source ZIP needed** to install the app. Developer tools are only necessary for functionality that invokes compilers or builds locally; installing and launching the GUI does not require Xcode.

## Building a test DMG (maintainer)

From the repository root on a Mac with Xcode:

```bash
chmod +x scripts/*.sh
./scripts/release.sh
open releases
```

Output: `releases/Local-Update-Bridge-vX.Y.Z.dmg`. This default is **ad-hoc signed**, not notarized.

## Building an official signed/notarized DMG (maintainer)

1. Obtain an Apple Developer Program membership and install a **Developer ID Application** certificate in your login keychain.
2. Set a notarization keychain profile using Apple's `notarytool store-credentials` (App Store Connect API key or Apple ID app-specific password and Team ID).
3. Run:

```bash
export LUB_SIGN_IDENTITY='Developer ID Application: Your Company (TEAMID)'
export LUB_TEAM_ID='TEAMID'
export LUB_NOTARY_PROFILE='LUB-Notary'
./scripts/release.sh
```

The script builds a Release `.app`, checks its signature, creates a binary-only DMG, submits for notarization, staples the ticket, validates the staple and writes a SHA-256 file.

**Note:** notarization is not automatic if the profile is missing. Check Apple's current signing requirements for helper executables and app runtime capabilities before distributing. LUB runs scripts and writes to user-selected project directories; validate all of those workflows on another Mac.

## Publish to GitHub

In the GitHub repository, create a new **Release** tagged with the app's version (for example `v1.6.5`). Attach the notarized `.dmg` and matching `.sha256` file. Users download the DMG only; they do not need to clone the repository. GitHub's automatic source code archives may still appear for open-source repositories, but the DMG is the installation asset.

### Self-update compatibility

The legacy **source ZIP self-updater** currently creates an unsigned local build; this is **not** an appropriate way to replace an officially signed/notarized public installation. Until signed release verification is added, public users should update with the next official notarized DMG and replace the Applications bundle manually. Do not auto-replace a Developer ID-signed app with unsigned source output.
