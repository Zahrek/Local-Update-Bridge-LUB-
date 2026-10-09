# v1.6.9.8 — Optional Codex Preview Discovery

- Opt-in **Scan ChatGPT Codex previews** toggle in the update-discovery section.
- Recognizes manifest-based project updates and LUB self-update source ZIP packages from `codex-file-preview-*` directories under the current macOS user's temporary directory.
- **Choose Codex Folder…** manually adds a different preview location to LUB's existing approved watch folders.
- Read-only discovery; applying updates continues to require explicit confirmation.
- Does not enumerate the entire `/private/var/folders` tree, bypass permissions, or require Full Disk Access.
- Temporary preview content may expire; import ZIPs into the persistent LUB inbox if you want to retain them.
- Full Xcode compilation and permission behavior must be verified on macOS.