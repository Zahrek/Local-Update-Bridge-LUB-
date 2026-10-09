# LUB v1.6.9.9 — Version-aware update list

- State is derived from semantic release version and confirmed local install/backup records; never ZIP size.
- Current LUB release shows Current Version / Reapply Update.
- Older LUB releases with valid app backup show Previously Installed / Roll Back.
- Older LUB archives without a verified backup are not labelled as installed.
- Project patch records are associated with matching project destination.
- Files different from the recorded package show Modified Build / Review & Reinstall; this may include legitimate manual edits.
- All installations and reinstalls retain explicit review/confirmation.
- Native macOS build/self-update needs verification in Xcode.