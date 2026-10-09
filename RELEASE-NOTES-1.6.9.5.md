# Local Update Bridge v1.6.9.5

- LUB source packages matching the running bundle version now show **Current Version** in the available updates list.
- Matching entries are muted (grey), with **Reapply Update** instead of **Update LUB**. Double-click also opens the existing explicit build/backup/restart confirmation.
- Previously installed older releases still support rollback only when a validated app backup exists.
- When Latest only is selected, preserve the installed LUB release in the list for visibility.
- Version metadata is 1.6.9.5 (build 1695).

Reapplication runs the existing source updater and requires the full Xcode/Swift toolchain. Public signed binaries should use a signed release-update workflow instead.
