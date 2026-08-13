# Toolchains

This tree contains optional, separately packaged toolchains. Its build sources
and outputs are not copied into the primary Altivec Intelligence image. GitHub
Actions uses the already-built image as the host environment and publishes the
finished packages as assets of the matching Altivec Intelligence release.

The directory convention intentionally leaves room for future targets:

```text
toolchain/<platform>/common/
toolchain/<platform>/<runtime-architecture>/
```

Only the iOS armv7 package exists today. No arm64, aarch64, or macOS toolchain
package is implemented by this layout. The package has a minimum deployment
target of iOS 6 and deliberately contains neither an Apple SDK nor ARCLite;
its SDK manager installs user-supplied SDK archives after deployment.
