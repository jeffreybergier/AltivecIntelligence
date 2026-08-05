# Common iOS Toolchain Inputs

These helpers are shared iOS package inputs:

- `altivec-app.sh` initializes an application from a supplied template.
- `altivec-profile.sh` configures the installed `/var/altivec` environment.
- `altivec-sdk.sh` manages SDKs and selects an architecture supported by both
  the installed compiler and SDK.
- `iphoneos-sdk-catalog.json` pins the supported SDK downloads and checksums.
- `sdk-manager-check.sh` validates the SDK manager and catalog together.

The armv7 package references these files from `../common/helpers`; it installs
them at the same device paths used before the monorepo import.
