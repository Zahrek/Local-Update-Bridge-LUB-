# LUB 1.6.9 — self-update recovery and DMG discoverability

- Always expose **Convert Selected Project to DMG…** in its own row under project controls. Requires full Xcode and a macOS app scheme; the DMG is placed in that project's releases directory.
- LUB source releases matching the running version are greyed out as **Installed**. Older releases with a real backup of the corresponding app are greyed out as **Previously installed** and offer **Roll Back…** on double-click and via button. Older releases without a verified backup cannot be rolled back.
- Rollback uses the existing external verified-app replacement helper, which backs up the current app as part of the swap.
- The external updater now retries the bundle-specific relaunch five times, checks whether its executable actually runs, restores the previous app on failed launch, and writes diagnostic logs to `~/Library/Logs/Local Update Bridge`.
- Real macOS runtime testing is still required; this package was not compiled with Xcode in this environment.

## Important limits
- Backups made by the earlier updater in the same installed-app directory are the only rollback choices. Merely possessing an old source ZIP does not constitute an installed backup.
- In-place replacement requires write access to the application folder. For publicly signed/notarized applications, use the separate signed-release updater rather than compiling an unsigned source ZIP.
