FROM ubuntu:22.04 AS altivec-builder

# 1. Install Dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    # --- Core system / base ---
    bash \
    ca-certificates \
    xdg-utils \
    file \
    # --- Text editors ---
    vim \
    nano \
    # --- Build essentials / toolchain ---
    build-essential \
    make \
    patch \
    clang \
    llvm-dev \
    lld \
    lldb \
    # --- Compiler & math libs (GCC toolchain deps) ---
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    # --- Core libraries / dev headers ---
    libxml2-dev \
    libssl-dev \
    libz-dev \
    uuid-dev \
    # --- Build systems / scripting ---
    bc \
    cmake \
    python3 \
    python3-distutils \
    m4 \
    texinfo \
    # --- Parser / compiler tools ---
    flex \
    bison \
    # --- Archive / compression ---
    tar \
    xz-utils \
    bzip2 \
    gzip \
    cpio \
    zip \
    # --- Version control ---
    git \
    # --- Networking / transfer ---
    curl \
    wget \
    rsync \
    ssh \
    iputils-ping \
    sshpass \
    socat \
    netcat-openbsd \
    avahi-utils \
    # --- CLI utilities / productivity ---
    jq \
    ripgrep \
    fd-find \
    tree \
    sqlite3 \
    shellcheck \
    # --- Image / icon tooling ---
    imagemagick \
    icnsutils \
    webp \
    optipng \
    jpegoptim \
    librsvg2-bin \
    # --- Audio / video transcoding ---
    ffmpeg \
    # --- macOS app bundle / packaging ---
    libplist-utils \
    xmlstarlet \
    # --- Reverse engineering / binary + protocol analysis ---
    xxd \
    binwalk \
    thrift-compiler \
    golang-go \
    mitmproxy \
    strace \
    ltrace \
    # --- Ruby / Jekyll static-site toolchain ---
    ruby-full \
    libffi-dev \
    # --- Document conversion ---
    pandoc \
    # --- Misc / extra tools ---
    wabt \
    && rm -rf /var/lib/apt/lists/*

# 1b. Bundler — install the current release from RubyGems. apt's
#      `bundler` is pinned to an older version that newer Gemfile.lock
#      files (via their `BUNDLED WITH` line) frequently refuse to accept.
RUN gem install bundler --no-document

# 2. Settings for the User

# Change to 1 less than the number of CPU cores on your computer
# Also make sure Docker is configured to use every CPU core
ENV JOBS=6

# Comment this out to make clang fully bootstrap itself
# This makes the build take significantly longer
ENV DISABLE_BOOTSTRAP=1

# 2. Set up environment

ENV GCC_VERSION=4.2.1
ENV APPLE_GCC=1
ENV SDK_VERSION=10.5
ENV OSX_VERSION_MIN=10.5
ENV UNATTENDED=1
ENV OSXCROSS_NO_DSYMUTIL=1
ENV INSTALLPREFIX=/osxcross/target
ENV LD_LIBRARY_PATH="/usr/lib/llvm-14/lib"

# 3. Install Radare to help with decompilation 
#    and reverse engineering (optional)

# NOTE: use the acr copy-install, NOT sys/install.sh — the latter is a
# developer install that symlinks /usr/local/bin/* back into the build
# tree, which the `rm -rf` below then deletes (→ dangling symlinks).
RUN curl -Ls https://github.com/radareorg/radare2/releases/download/6.1.4/radare2-6.1.4.tar.xz \
    | tar xJ \
    && cd radare2-6.1.4 \
    && ./configure --prefix=/usr \
    && make -j"$JOBS" \
    && make install \
    && cd / && rm -rf radare2-6.1.4 \
    && ldconfig \
    && radare2 -v

# 4. Copy OSXCross and build base toolchain
WORKDIR /osxcross
COPY docker/ ./docker/

# 5. Build OSXCross and Compilers

RUN echo "Pre-Build: Altivec Intelligence" \
      && ./docker/prebuild.sh

RUN echo "Build: osxcross" \
      && ./build.sh

RUN echo "Build: Apple GCC 4.2 (PPC)" \
      && POWERPC=1 ./build_gcc_ppc.sh \
      && rm -rf build
RUN echo "Build: Apple GCC 4.2 (i386 + x86_64)" \
      && ./build_gcc.sh \
      && rm -rf build

RUN echo "Post-Build: Altivec Intelligence" \
      && ./postbuild.sh \
      && rm -rf tarballs

ENV PATH="/osxcross/target/bin:${PATH}"

# 6. Node.js 22 LTS (matches wrangler's supported runtime)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# 7. Fix broken npm bundled with nodesource, then install globals
RUN curl -fsSL https://registry.npmjs.org/npm/-/npm-11.14.1.tgz -o /tmp/npm.tgz \
    && mkdir -p /tmp/npm-install \
    && tar xzf /tmp/npm.tgz -C /tmp/npm-install \
    && node /tmp/npm-install/package/bin/npm-cli.js install -g npm@11.14.1 \
    && rm -rf /tmp/npm.tgz /tmp/npm-install

RUN npm install -g \
      wrangler \
      jsdom \
      qrcode-terminal \
      @anthropic-ai/claude-code \
      @openai/codex \
      @earendil-works/pi-coding-agent \
      opencode-ai@latest \
      prettier \
      js-beautify \
      webcrack

# 7b. Antigravity CLI (Google's replacement for Gemini CLI)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin

# 8. rcodesign — real Apple code signer (osxcross only ships
#    codesign_allocate, which reserves space but cannot sign).
#    Prebuilt static musl binary from indygreg/apple-platform-rs.
#    NOTE: must be ARG, not ENV — rcodesign reads any RCODESIGN_*
#    env var as config, so a persistent ENV RCODESIGN_VERSION makes
#    every rcodesign invocation abort with "UnknownField(version)".
ARG RCODESIGN_VERSION=0.27.0
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) RC_ARCH=x86_64-unknown-linux-musl ;; \
      arm64) RC_ARCH=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported arch for rcodesign" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/rcodesign.tar.gz \
      "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN_VERSION}/apple-codesign-${RCODESIGN_VERSION}-${RC_ARCH}.tar.gz"; \
    tar -xzf /tmp/rcodesign.tar.gz -C /tmp; \
    install -m 0755 "/tmp/apple-codesign-${RCODESIGN_VERSION}-${RC_ARCH}/rcodesign" /usr/local/bin/rcodesign; \
    rm -rf /tmp/rcodesign.tar.gz "/tmp/apple-codesign-${RCODESIGN_VERSION}-${RC_ARCH}"; \
    rcodesign --version

# 8b. ldid — pseudo-signer + entitlements editor for jailbroken iOS.
#     Statically-linked binary from ProcursusTeam (musl-based; no glibc
#     dependency on the host). Complements rcodesign above: rcodesign
#     handles real-cert signing; ldid is the canonical tool for the
#     ad-hoc / entitlements workflow that jailbreak tooling expects.
ARG LDID_VERSION=v2.1.5-procursus7
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) LDID_ASSET=ldid_linux_x86_64 ;; \
      arm64) LDID_ASSET=ldid_linux_aarch64 ;; \
      *) echo "unsupported arch for ldid" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/ldid \
      "https://github.com/ProcursusTeam/ldid/releases/download/${LDID_VERSION}/${LDID_ASSET}"; \
    chmod +x /usr/local/bin/ldid; \
    ldid 2>&1 | grep -q "Link Identity Editor"

# 8c. ipsw — blacktop's Mach-O analysis multi-tool. `ipsw class-dump`
#      reconstructs Obj-C (and Swift) @interface declarations straight
#      from a Mach-O binary: the Linux-native stand-in for the classic
#      macOS class-dump, which Ubuntu does not package for apt. Shipped
#      as a prebuilt Go release binary, installed like rcodesign/ldid.
#      NOTE: the release ships BOTH `ipsw` (CLI) and `ipswd` (daemon) —
#      we deliberately install only the `ipsw` binary. The git tag is
#      v-prefixed (vX.Y.Z) but the asset filename is not (X.Y.Z).
ARG IPSW_VERSION=3.1.687
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) IPSW_ARCH=x86_64 ;; \
      arm64) IPSW_ARCH=arm64 ;; \
      *) echo "unsupported arch for ipsw" >&2; exit 1 ;; \
    esac; \
    mkdir -p /tmp/ipsw-install; \
    curl -fsSL -o /tmp/ipsw.tar.gz \
      "https://github.com/blacktop/ipsw/releases/download/v${IPSW_VERSION}/ipsw_${IPSW_VERSION}_linux_${IPSW_ARCH}.tar.gz"; \
    tar -xzf /tmp/ipsw.tar.gz -C /tmp/ipsw-install; \
    install -m 0755 "$(find /tmp/ipsw-install -type f -name ipsw | head -n1)" /usr/local/bin/ipsw; \
    rm -rf /tmp/ipsw.tar.gz /tmp/ipsw-install; \
    ipsw version

# 9. Working Directory & Runtime
WORKDIR /repo/altivec
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["/bin/bash"]

# Put /altivec/bin on PATH so altivec-deploy and altivec-chooser are
# callable by bare name (no ./ prefix, no .sh extension). Lives in the
# base stage so the dev compose (which bind-mounts the repo at /altivec
# and targets altivec-builder) gets the same PATH as the prebuilt GHCR
# image — the bind-mount supplies the files at runtime.
ENV PATH="/altivec/bin:${PATH}"

# 10. GHCR image layer — bakes the Altivec runtime repo into /altivec/.
#     Builds the shared AltivecCore and AltivecCocoa artifacts and ships their
#     build outputs in the image so GHCR consumers do NOT have to
#     re-run the slow cross-compile locally. The top-level `make all`
#     target for each library produces BOTH:
#       - Static libs: libcurl.a, libssl.a, libcrypto.a, libz.a,
#         libAICURLConnection.a, libsqlite3.a, libcjson.a
#         (Mac: ppc/i386/x86_64/arm64; Phone: armv7/arm64).
#       - Dynamic AltivecCore.framework (versioned bundle on Mac, flat
#         bundle on iPhone) — same architectures as the static libs.
#       - Dynamic AltivecCocoa.framework and libAltivecCocoa.a for Mac
#         (ppc/i386/x86_64/arm64) and iPhone (currently empty,
#         armv7/arm64).
#     The mk files in altivec_common_*.mk expect these build outputs under
#     $(ALTIVEC_ROOT)/libs/{core,cocoa}/build-* — those paths resolve to
#     /altivec/libs/{core,cocoa}/build-* here.
#     Only built when explicitly targeted (docker compose skips it).
FROM altivec-builder AS ghcr-action
WORKDIR /altivec

# Build AltivecCore first so this slow layer is not invalidated by trivial
# changes elsewhere in the repo. `make all` builds both the static .a
# libs AND the dynamic AltivecCore.framework into build-{mac,phone}/lib/
# (alongside headers in build-{mac,phone}/include/). Those trees are
# preserved in the final image — that is the whole point of this stage.
# prune-intermediates drops Core sources/objects/stamps while keeping the
# build-*/lib (static libs + framework bundle + cacert.pem) and
# build-*/include trees apps actually link against; done in the same
# RUN so the intermediates never form their own layer.
COPY libs/libcurl/ ./libs/libcurl/
COPY libs/sqlite/  ./libs/sqlite/
COPY libs/core/    ./libs/core/
RUN cd libs/core && make all && make prune-intermediates

# Build AltivecCocoa before sample apps so CURLmac can embed the Mac
# framework and CURLphone can statically link the phone archive.
COPY libs/cocoa/   ./libs/cocoa/
RUN cd libs/cocoa && make all && make prune-intermediates

# Common mk fragments must land before the apps build below — each app's
# Makefile does `include /altivec/altivec_common_{mac,phone}.mk` by
# absolute path.
COPY altivec_common_mac.mk   ./
COPY altivec_common_phone.mk ./

# Bake prebuilt sample apps into the image so consumers get ready-to-run
# .app bundles (Mac quad-fat: ppc/i386/x86_64/arm64; Phone dual:
# armv7/arm64) without needing to compile anything. This also doubles as
# an end-to-end CI smoke test — any regression in AltivecCore, the mk
# fragments, or the toolchain will fail this step long before users hit
# it. Outputs land in apps/*/build-release/ and survive in the final
# image. Kept as a separate RUN from the libcurl build above so trivial
# app-source edits do not invalidate the multi-hour libcurl layer.
COPY apps/                   ./apps/
RUN set -e; \
    for app in SingleWindow SingleScreen CURLmac CURLphone; do \
      echo "=== Building $app (release) ==="; \
      make -C apps/$app release; \
    done; \
    test -d apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCore.framework; \
    test -d apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework; \
    test -f apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework/Resources/Fonts/FA7-Solid-900.otf; \
    test -f apps/CURLmac/build-release/CURLmac.app/Contents/Frameworks/AltivecCocoa.framework/Resources/Fonts/LICENSE-Font-Awesome.txt; \
    test -f libs/core/build-phone/lib/AltivecCore.framework/AltivecCore; \
    test -f libs/cocoa/build-phone/lib/AltivecCocoa.framework/AltivecCocoa; \
    test -f libs/cocoa/build-phone/lib/AltivecCocoa.framework/Fonts/FA7-Solid-900.otf; \
    test -f libs/cocoa/build-phone/lib/AltivecCocoa.framework/Fonts/LICENSE-Font-Awesome.txt; \
    test -f apps/CURLphone/build-release/CURLphone.app/Fonts/FA7-Solid-900.otf; \
    test -f apps/CURLphone/build-release/CURLphone.app/Fonts/LICENSE-Font-Awesome.txt; \
    test ! -d apps/CURLphone/build-release/CURLphone.app/Frameworks

# Bake the rest of the runtime repo into /altivec/. Build-time-only files
# (Containerfile, compose.yml, docker/, .github/) are deliberately
# excluded. Kept after the apps build so edits to docs/README/bin/
# templates do not invalidate the apps layer.
COPY AGENTS.md               ./
COPY README.md               ./
COPY LICENSE                 ./
COPY bin/                    ./bin/
COPY docs/                   ./docs/
COPY templates/              ./templates/

# Recreate the AGENTS.md aliases that AI agents look for by name.
RUN ln -sf AGENTS.md CLAUDE.md \
 && ln -sf AGENTS.md GEMINI.md
