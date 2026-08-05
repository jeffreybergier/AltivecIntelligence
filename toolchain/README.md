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
package is implemented by this layout.

One armv7 payload file is also an input to the primary image:
`iOS/armv7/payload/lib/arc/libarclite_iphoneos.a`. Clang needs that archive to
link the image's existing iOS 4.3 ARC applications; the rest of this tree is
used only by the release-extras workflow.
