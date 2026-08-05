# iOS Toolchains

`common` contains iOS package inputs that are already architecture-aware or
architecture-neutral. Architecture-specific compiler, linker, packaging,
library-manager, and application-template logic stays in its architecture
directory.

The only implemented package is [`armv7`](armv7/). A future implementation may
add another architecture beside it and reuse only the pieces that genuinely
belong in [`common`](common/). The presence of this namespace is not a claim
that an arm64 toolchain package currently exists.
