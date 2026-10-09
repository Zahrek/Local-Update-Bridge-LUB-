# Updating LUB from within LUB

1. Copy the LUB source release ZIP to Downloads or a configured watched folder.
2. Click **Scan Now** (or wait for the 12-second idle scan).
3. The release appears as **Local Update Bridge** with an **Update LUB** action.
4. Review the confirmation dialog; LUB builds a replacement app via its bundled trusted recipe, backs up the current app, installs and restarts.

No project folder is required for self updates. Existing source ZIPs without the metadata file are recognized by their required source files; new releases include `lub-self-update.json` for version tracking.

**Security:** LUB self-update executes newly compiled code. Only accept source ZIPs from trustworthy sources. The release manifest is descriptive metadata, not cryptographic provenance verification. No automatic installation occurs without user confirmation.

**Note:** The already-installed LUB version must contain this feature before it can discover self-release ZIPs. For the first upgrade, build and launch this source once.
