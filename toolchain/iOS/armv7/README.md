# Altivec Toolchain for iOS armv7

This directory builds the optional `.deb` toolchain for jailbroken armv7 iOS
devices. It was imported from the former AltivecChain repository at commit
`2039806cfaf6ddf1a7976f4f8766ba4d12ac5841` and now shares selected iOS helpers
from `../common`.

From this directory, the usual entry points are:

```bash
make check
make release DEB_VERSION=1.2.3
```

Build parallelism automatically matches the CPUs visible to the container or
host. Override it when needed, for example with `make release JOBS=4`.

All generated state stays under the ignored `build-release/` directory. The
tag release workflow builds the core-tools and LLVM payload archives in
parallel, then runs the packaging-only `deb` target with the Altivec
Intelligence release version.

The workflow caches those two packaged payload archives using a key that
includes the exact candidate-image digest and the contents of both `iOS/common`
and `iOS/armv7`. GitHub scopes tag caches to that tag, so this primarily makes
a full rerun of the same expensive release safe and fast; separate release
tags still build from their exact candidate image.

This is an armv7-only implementation. The parent directory reserves space for
future architectures, but this build does not produce or promise an arm64
package.

The repository's MIT license covers the Altivec-authored build scripts and
templates. The resulting iOS 6+ package contains independently licensed
upstream software, but deliberately contains neither an Apple SDK nor ARCLite.
Its SDK manager installs a checksum-verified, user-supplied SDK after deployment.
Review the upstream redistribution obligations before publishing the package.
