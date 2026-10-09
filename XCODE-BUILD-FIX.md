# Xcode build-script sandbox correction

Removed the `Make packaged helpers executable` Run Script build phase, which
attempted `chmod` inside the built `.app` and triggered `Sandbox: chmod deny`.
The original CLI and helper scripts are stored with executable permission.

After opening this project in Xcode, choose Product > Clean Build Folder and build.
For existing projects, ensure Git tracks the executable bit (`git update-index --chmod=+x`).
This corrects the sandbox-denied chmod errors; native macOS compilation still
needs to be confirmed locally.
