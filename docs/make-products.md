# Declarative Make products

Set `PRODUCTS` and include the existing `altivec_common_mac.mk` or
`altivec_common_phone.mk` entry point. `altivec_common_host.mk` uses the same
graph for native offline harnesses. The original `APP_NAME` interface remains
available for existing images/examples; new projects should use products.

```make
PRODUCTS = MyApp worker model
MyApp_TYPE = app
MyApp_SOURCES = main.m WindowController.m
MyApp_DEPS = model
MyApp_EMBED = worker
MyApp_PLIST = Resources/Info.plist
MyApp_RESOURCES = Resources/icon.icns
MyApp_LDFLAGS = -framework AppKit -lobjc
worker_TYPE = daemon
worker_SOURCES = worker.c
worker_DEPS = model
model_TYPE = static
model_SOURCES = model.c
include /altivec/altivec_common_mac.mk
```

Each product is an `app`, `executable`, `daemon`, or `static` library. `DEPS`
is an ordered list of product dependencies (static libraries are linked in
that order). `EMBED` adds executables to an app and makes their signed outputs
bundle prerequisites. `INSTALL` adds separately installed executables to a
DEB. Dependency products are built before consumers. `PACKAGE_PRODUCTS`
selects top-level products to archive; by default dependencies/helpers are
excluded. `make <product>` builds a named product without packaging everything.

## Paths and invocation

Every project entry includes `make/entry.mk` before evaluating its declarations,
then places those declarations inside `ifeq ($(_altivec_relocated),)` / `endif`.
This lets `make -f /path/to/Makefile` re-enter the Makefile's directory before
resolving sources, exactly like `make -C /path/to`. Templates show the complete
wrapper. Child declarations anchor `PROJECT_ROOT` to their Makefile location;
root orchestration exports absolute `PROJECT_ROOT` and `BUILD_ROOT` to children.
No Git checkout is needed. Relative `BUILD_ROOT` overrides are relative to the
project root. Whitespace in roots is rejected explicitly.

When upgrading an existing checkout, run `make clean` before its first build:
old flat executable names can occupy the new product-directory locations.
Existing build caches are disposable; prebuilt image libraries are unaffected.

The default layout is:

```text
build/<platform>/<debug|release>/<product>/<bundle, executable, archive, dSYMs>
build/<platform>/<debug|release>/<product>/Intermediates/<architecture>/<source>.o
build/<platform>/<debug|release>/generated/
build/analyze/<platform>/<product>/<source>.plist
build/tests/<platform>/<suite>/
build/release/                         # staged release assets and manifest
```

Static library product directories default to `lib<product>`; other types use
the product name. `<product>_OUTPUT_NAME` overrides this directory component.
Output names are checked for case-insensitive collisions (for example RetroDLP
and retrodlp on a Mac filesystem), even when building on Linux.

Platforms are `macOS`, `iOS`, and `linux` (native host builds). Full source paths
and extensions distinguish same-named C, C++, Objective-C and Objective-C++
inputs. Modern slice dSYMs stay next to the product; legacy debug information
stays embedded. `SYMBOLS=0` disables dSYM generation for mock toolchains.

A root Makefile delegates without implementing build recipes:

```make
ALTIVEC_ROOT ?= /altivec
include $(ALTIVEC_ROOT)/make/entry.mk
ifeq ($(_altivec_relocated),)
PROJECT_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
PLATFORMS = macOS iOS
PROJECT_macOS_DIR = source/macOS
PROJECT_iOS_DIR = source/iOS
include $(ALTIVEC_ROOT)/make/projects.mk
endif
```

`make -j debug release` uses independent configurations. Public builds sharing
a platform/configuration wait on a filesystem lock, so simultaneous SDK, flag,
and architecture overrides cannot overwrite each other's in-progress products.
Stamps invalidate sequential changes. For persistent, concurrently usable
variants use `BUILD_VARIANT=arm64-dev` (letters, digits, `_`, `-`); its outputs
live under `<platform>/<configuration>/variants/<variant>/<product>`. Use the same variant
for consumers and validation. Dependency copies follow the variant as well.

`make clean PRODUCT=MyApp` removes only that product across configurations and
variants on the selected platform; `make macOS-clean` removes macOS outputs,
analyzer reports, tests, and dependency copies. `make clean-all` explicitly
removes the entire selected build root, including generated and staged assets.
Cleanup waits for active public builds. Ignored sibling `.NAME.altivec-locks`
directories preserve lock identity across whole-root cleanup and across containers.
Atomic directory locks also coordinate Docker Desktop with the Mac host. After a
forced process/container kill, inspect `owner.json` and remove only the abandoned
lock directory once its owner and child builds have stopped. Roots, ancestors, source/metadata paths,
tracked files, and redirected output ancestors are rejected. Directory symlinks
are never followed by cleanup. A committed `.altivec-project` identity lets
output ownership survive different host/container mount paths; legacy absolute
ownership markers are upgraded when used. Prebuilt `/altivec/libs/*/build-mac`
and `build-phone` remain unchanged.

Put configuration-dependent generator outputs beneath `$(GENERATED_DIR)`.
Declare `GEN_<name>_OUTPUT`, `GEN_<name>_INPUTS`, and `GEN_<name>_COMMAND`, and
add that output to the product's `GENERATED` inputs. Share an output across
configurations only when its generator and contents are configuration-independent.
Generators lock their destination and record the command/input identity before
reusing it. Generated font maps in Strappy now use configuration-specific trees.

## Architectures, compilers and languages

`ARCHS` defaults to `ppc i386 x86_64 arm64` on Mac and `armv7 arm64` on iOS.
Use `ARCHS="ppc i386"` for a legacy product or `ARCHS=arm64` for development.
For each slice, `CC_<arch>`, `CXX_<arch>`, `AR_<arch>`, `SDK_<arch>` and
`MIN_<arch>` are public settings. Default floors are Mac 10.4/10.4/10.9/11.0
and iOS 5.0/7.0. Unsupported architectures and lower floors fail validation.
Every external static archive and dynamic framework is checked for the
requested architecture before linking. x86_64 links with LLVM ld64 to retain
the CPU capability bit that prevents Tiger selecting the wrong slice.

`<product>_SOURCES` and `<product>_SOURCES_<arch>` list paths. `SOURCE_DIRS`
provides optional lookup directories. Source groups let a product share an
inventory while preserving its own compile policy:

```make
Client_GROUPS = ui model
GROUP_ui_SOURCES = main.m ViewController.mm
GROUP_ui_MEMORY = arc
GROUP_ui_OBJCFLAGS = -Wconversion
GROUP_model_SOURCES = model.c bridge.m
GROUP_model_CFLAGS = -std=gnu99
```

MRC is the default. `MEMORY=arc` is allowed only on iOS groups; it applies only
to Objective-C/Objective-C++ files, not C/C++. Mac groups remain MRC, including
Tiger. Flags are layered as follows:

- `CPPFLAGS`, `BUILD_FLAGS`, and language flags `CFLAGS`, `CXXFLAGS`,
  `OBJCFLAGS`, `OBJCXXFLAGS`;
- `<product>_FLAGS`, `_FLAGS_<arch>`, `_<language>FLAGS`, and
  `_<language>FLAGS_<arch>`;
- `GROUP_<group>_FLAGS`, `_FLAGS_<arch>`, and `_<language>FLAGS`.

Use `<product>_LDFLAGS` / `_LDFLAGS_<arch>` for framework/system link flags and
`_STATIC_LIBS` / `_STATIC_LIBS_<arch>` for archive paths. Archive inputs are
visible Make prerequisites. Header depfiles and configuration stamps track
source, compiler, SDK, flags and dependency changes. `CORE=static|dynamic` and
`COCOA=static|dynamic` opt individual products into engine libraries; iOS uses
static linkage. App fonts/licenses, certificates and dynamic frameworks are
staged automatically when selected.

## Generated inputs, resources and signing

| Product input | Meaning |
| --- | --- |
| `INPUTS` | Additional file prerequisites, including helper plists |
| `GENERATED` | Generated files required before compilation |
| `RESOURCES` | Files/directories copied by basename into the resource root |
| `RESOURCE_BUNDLES` | Nested bundles, copied intact |
| `RESOURCE_MAP` | `source=relative/destination` resource mappings |
| `RESOURCE_EXCLUDES` | Explicit relative paths excluded after staging |
| `FONTS` | Font files and licenses copied into `Fonts/` |
| `LOCALIZATIONS` | `.lproj` directories or their parent; Mac strings become UTF-16 |
| `EMBED` / helper `EMBED_PATH` | Signed products placed at bundle-relative destinations |
| `ENTITLEMENTS` / `SIGN=1` | Per-executable signing; unsigned link outputs are preserved |
| `MAC_SIGN=1` | Modern Mac signing while preserving untouched legacy slices |
| `SIGN_PLIST`, `IDENTIFIER`, `SIGN_PEM` | Optional Mac signing metadata/identity |

Resources are tracked recursively, including additions/removals. Rebuilding a
bundle reconstructs it so deleted resources cannot survive in an archive.
iOS signing uses ldid. Mac signing uses rcodesign on modern slices and leaves
Tiger slices untouched (including when entitlements are supplied).
Each executable owns its signing policy; app entitlements are never inherited
by a helper. `SANDBOX=container|unsandboxed` validates the declared entitlement
policy independently of package format or install prefix.

Declare application-specific generators using `GENERATORS`,
`GEN_<id>_OUTPUT`, `_INPUTS`, and `_COMMAND`. Generated outputs are normal
prerequisites; shared generator outputs are locked and rechecked across
concurrent configurations. Use `$(OUTPUT_DIR)` for generated files whose
contents differ between configurations. Generator commands and inputs are
tracked by stamps. Commands are the escape hatch for app-specific
code generation, not a place to reproduce compile/link/sign/package recipes.

`DEPENDENCIES=libical libvc` enables shared adapters for the pinned legacy
library layouts used by rCloud. Products opt in with `_DEPENDENCIES`. The
adapters patch isolated build copies, never submodules. Checkout roots are
`LIBICAL_SOURCE` and `LIBVC_SOURCE`; generated headers are compile prerequisites.

## Packages and tests

`<product>_PACKAGES` accepts `zip`, `ipa`, `deb-rootful`, `deb-rootless`.
Mac apps default to ZIP, iOS apps to IPA, and CLI/library products to ZIP.
`PACKAGE_RESOURCES` supplies additional `source=path` members for CLI/library
ZIPs (for example CA certificates, public headers, licenses and examples).
`ARCHIVE_NAME` changes the archive basename, and `PACKAGE_MAIN_PATH` places
a CLI/library payload at an explicit archive-relative path (for example
`lib/libmodel.a`).

DEBs explicitly declare `PACKAGE_ID`, `VERSION`, `PACKAGE_ARCH`, and optionally
`MAINTAINER`, `DESCRIPTION`, `COMPRESSION` (default gzip), `OWNER` (currently
`0:0`), `PREFIX_deb-rootful`, and `PREFIX_deb-rootless` (default `/var/jb`).
Supported package architectures are `all`, `iphoneos-arm`, and
`iphoneos-arm64`; none is inferred from the variant. Strappy chooses `all` and
rCloud chooses `iphoneos-arm`. Rootless changes installation paths; it does not
change sandbox policy. A Retro-DLP rootless package can retain its app container.

`INSTALL` helpers use their own `INSTALL_PATH` (default `usr/libexec/<name>`).
`LAUNCHD` lists plists, `PACKAGE_FILES` supplies `source=install/path` mappings,
and `PACKAGE_SCRIPTS` lists `preinst`, `postinst`, `prerm`, `postrm` files (an
optional `.in` suffix is stripped). `@PREFIX@` is expanded consistently.
`LIFECYCLE` can inject common project-specific shell functions at an
`# ALTIVEC_LIFECYCLE` marker. Lifecycle scripts are packaged, never executed by
build/validation. App plist and DEB versions must agree.

- `help` lists conventions.
- `print-config` reports output paths, products, sources, required inputs,
  compilers, SDKs, architectures and deployment floors without compiling.
- `validate` checks paths/toolchains and policy.
- `validate-package` extracts archives, validates architecture slices and
  entitlements of every declared executable, plist metadata, DEB ownership,
  launchd paths and lifecycle shell syntax.
- `test-host` runs `TEST_HOST_COMMAND`, or the engine's offline contract suite.
- `test-native` runs the explicitly supplied offline `TEST_NATIVE_COMMAND`;
  it fails clearly if none is configured, rather than claiming a device test.
- `analyze` runs Clang's analyzer using `ANALYZE_ARCH` and the same source flags.

`test/fixtures/{simple,daemon,products}` are small declarative examples.
`python3 test/test_make_products.py` checks dependency behavior without SDKs;
`bash test/test_make_products_container.sh` runs the same fixtures against
real SDKs, both configurations, subset signing and a container-preserving
rootless DEB. Use network-disabled
containers for offline testing. Container build dependency downloads are
separate from test execution. Runtime module copies are placed after the
expensive toolchain/library image stage so module changes reuse that cache.
