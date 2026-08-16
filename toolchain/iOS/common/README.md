# Common iOS Toolchain Inputs

These helpers are shared iOS package inputs:

- `altivec-app.sh` initializes an application from a supplied template.
- `altivec-profile.sh` configures the installed `/var/altivec` environment.
- `altivec-sdk.sh` verifies, installs, reports, and uninstalls the single
  supported iPhoneOS 8.4 SDK. It reads `iPhoneOS8.4.sdk.tar.gz` from root's
  home folder (`/var/root`) and never downloads it.
- `../../../share/altivec-sdk/catalog.json` pins the supported SDK archive
  filenames, checksums, architectures, and deployment targets.
- `sdk-manager-check.sh` validates the SDK manager and catalog together.

The armv7 package references these files from `../common/helpers`; it installs
them at the same device paths used before the monorepo import.
