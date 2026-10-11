# @ALTIVEC_DISPLAY_NAME@

This repository was created by `altivec-app`. Portable C and shared resources
live under `source/shared`; UIKit source, bundle metadata, and iPhone artwork
live under `source/iOS`.

Build from the repository root:

```sh
make clean
make analyze
make release
```

The signed application and IPA are written beneath
`source/iOS/build-release`. Replace the placeholder app icons before shipping.
The included launch images are opaque white canvases matching the starter
view. To replace them from a reviewed master image, run:

```sh
tools/generate-launch-images.sh --master /path/to/LaunchScreenMaster.png --force
```
