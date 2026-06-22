# syntax=docker/dockerfile:1.7
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
    libcurl4-openssl-dev \
    libsqlite3-dev \
    libxml2-dev \
    libssl-dev \
    libz-dev \
    uuid-dev \
    # --- Build systems / scripting ---
    bc \
    cmake \
    python3 \
    python3-distutils \
    python3-yaml \
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

ENV CURL_RETRY_FLAGS="--fail --silent --show-error --location --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 30"

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

# Keep generic native build tools pointed at Ubuntu's toolchain even though the
# osxcross tools are on PATH. Project makefiles still invoke Apple cross tools
# explicitly, while npm/gem native extensions use these defaults.
ENV CC=/usr/bin/gcc \
    CXX=/usr/bin/g++ \
    LD=/usr/bin/ld \
    AR=/usr/bin/ar

# Host bind mounts often carry the macOS UID/GID, so Git running as root inside
# the container otherwise rejects them as dubious ownership.
RUN git config --system --add safe.directory "*"

# 3. Install Radare to help with decompilation 
#    and reverse engineering (optional)

# NOTE: use the acr copy-install, NOT sys/install.sh — the latter is a
# developer install that symlinks /usr/local/bin/* back into the build
# tree, which the `rm -rf` below then deletes (→ dangling symlinks).
RUN curl $CURL_RETRY_FLAGS -o /tmp/radare2.tar.xz \
      https://github.com/radareorg/radare2/releases/download/6.1.4/radare2-6.1.4.tar.xz \
    && tar xJf /tmp/radare2.tar.xz \
    && cd radare2-6.1.4 \
    && ./configure --prefix=/usr \
    && make -j"$JOBS" \
    && make install \
    && cd / && rm -rf radare2-6.1.4 /tmp/radare2.tar.xz \
    && ldconfig \
    && radare2 -v

# 4. Copy OSXCross and build base toolchain
WORKDIR /osxcross
COPY docker/ ./docker/

# 5. Build OSXCross and Compilers
# Keep SDK/GCC source tarballs out of committed image layers. They are large,
# and leaving them in an early layer can make the final image export fail even
# when a later layer deletes /osxcross/tarballs.

RUN --mount=type=cache,id=altivec-osxcross-tarballs,target=/osxcross/tarballs,sharing=locked \
    echo "Pre-Build: Altivec Intelligence" \
      && ./docker/prebuild.sh

RUN --mount=type=cache,id=altivec-osxcross-tarballs,target=/osxcross/tarballs,sharing=locked \
    echo "Build: osxcross" \
      && ./build.sh

RUN --mount=type=cache,id=altivec-osxcross-tarballs,target=/osxcross/tarballs,sharing=locked \
    echo "Build: Apple GCC 4.2 (PPC)" \
      && POWERPC=1 ./build_gcc_ppc.sh \
      && rm -rf build
RUN --mount=type=cache,id=altivec-osxcross-tarballs,target=/osxcross/tarballs,sharing=locked \
    echo "Build: Apple GCC 4.2 (i386 + x86_64)" \
      && ./build_gcc.sh \
      && rm -rf build

RUN --mount=type=cache,id=altivec-osxcross-tarballs,target=/osxcross/tarballs,sharing=locked \
    echo "Post-Build: Altivec Intelligence" \
      && ./postbuild.sh

ENV PATH="/osxcross/target/bin:${PATH}"

# 6. Node.js 22 LTS (matches wrangler's supported runtime)
RUN curl $CURL_RETRY_FLAGS -o /tmp/nodesource-setup.sh \
      https://deb.nodesource.com/setup_22.x \
    && bash /tmp/nodesource-setup.sh \
    && rm -f /tmp/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# 7. Fix broken npm bundled with nodesource, then install globals
RUN curl $CURL_RETRY_FLAGS -o /tmp/npm.tgz \
      https://registry.npmjs.org/npm/-/npm-11.14.1.tgz \
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
RUN curl $CURL_RETRY_FLAGS -o /tmp/antigravity-install.sh \
      https://antigravity.google/cli/install.sh \
    && bash /tmp/antigravity-install.sh --dir /usr/local/bin \
    && rm -f /tmp/antigravity-install.sh

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
    curl $CURL_RETRY_FLAGS -o /tmp/rcodesign.tar.gz \
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
    curl $CURL_RETRY_FLAGS -o /usr/local/bin/ldid \
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
    curl $CURL_RETRY_FLAGS -o /tmp/ipsw.tar.gz \
      "https://github.com/blacktop/ipsw/releases/download/v${IPSW_VERSION}/ipsw_${IPSW_VERSION}_linux_${IPSW_ARCH}.tar.gz"; \
    tar -xzf /tmp/ipsw.tar.gz -C /tmp/ipsw-install; \
    install -m 0755 "$(find /tmp/ipsw-install -type f -name ipsw | head -n1)" /usr/local/bin/ipsw; \
    rm -rf /tmp/ipsw.tar.gz /tmp/ipsw-install; \
    ipsw version

# 9. Working Directory & Runtime
WORKDIR /repo/altivec
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["/bin/bash"]

# Put /altivec/bin on PATH so altivec-deploy, altivec-release, and
# altivec-chooser are
# callable by bare name (no ./ prefix, no .sh extension). Lives in the
# base stage so the dev compose (which bind-mounts the repo at /altivec
# and targets altivec-builder) gets the same PATH as the prebuilt GHCR
# image — the bind-mount supplies the files at runtime.
ENV PATH="/altivec/bin:${PATH}"

# Runtime caches should not default into /root, because many project compose
# files bind-mount ~/.altivec there. /cache is intended to be backed by a
# disposable named Docker volume in compose files.
ENV ALTIVEC_CACHE=/cache \
    XDG_CACHE_HOME=/cache/xdg \
    NODE_COMPILE_CACHE=/cache/node/compile \
    COREPACK_HOME=/cache/corepack \
    npm_config_cache=/cache/npm \
    YARN_CACHE_FOLDER=/cache/yarn \
    PNPM_HOME=/cache/pnpm \
    GOPATH=/cache/go \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go-build \
    BUNDLE_USER_HOME=/cache/bundle \
    BUNDLE_USER_CACHE=/cache/bundle/cache \
    BUNDLE_USER_CONFIG=/cache/bundle/config \
    BUNDLE_PATH=/cache/bundle/install \
    GEM_SPEC_CACHE=/cache/gem/specs

RUN mkdir -p /cache

# Runtime helper scripts live in altivec-builder so every downstream image
# stage inherits host-architecture-correct tools. `altivec-release` is an
# interpreted Python script, but this placement keeps script validation and
# future generated helpers in the per-architecture builder stage.
COPY bin/ /altivec/bin/
RUN chmod +x /altivec/bin/* \
 && altivec-release --help >/dev/null

# 10. GHCR image layer — bakes the Altivec runtime repo into /altivec/.
#     Builds the shared AltivecCore and AltivecCocoa artifacts and ships their
#     build outputs in the image so GHCR consumers do NOT have to
#     re-run the slow cross-compile locally. The top-level `make all`
#     target for each library produces:
#       - Mac static libs plus dynamic frameworks
#         (ppc/i386/x86_64/arm64).
#       - Phone static libs only (armv7/arm64), because embedded iOS
#         frameworks are not compatible with iOS 4.3-7 devices.
#     The mk files in altivec_common_*.mk expect these build outputs under
#     $(ALTIVEC_ROOT)/libs/{core,cocoa}/build-* — those paths resolve to
#     /altivec/libs/{core,cocoa}/build-* here.
#     Only built when explicitly targeted (docker compose skips it).
FROM altivec-builder AS ghcr-action
WORKDIR /altivec

# Build AltivecCore first so this slow layer is not invalidated by trivial
# changes elsewhere in the repo. `make all` builds the aggregate static
# archives, the Mac framework, headers, and cacert.pem into build-* trees.
# Dependency build trees are pruned afterward, but the component archives in
# libs/core/build-* are retained so release asset staging can package the same
# static library contents a direct `make all` build would produce.
COPY libs/libcurl/ ./libs/libcurl/
COPY libs/sqlite/  ./libs/sqlite/
COPY libs/core/    ./libs/core/
RUN --mount=type=cache,id=altivec-libcurl-tarballs,target=/altivec/libs/libcurl/tarballs,sharing=locked \
    --mount=type=cache,id=altivec-sqlite-tarballs,target=/altivec/libs/sqlite/tarballs,sharing=locked \
    set -e; \
    cd libs/core; \
    make all; \
    make prune-intermediates; \
    cd ../..; \
    rm -rf libs/libcurl/build-mac libs/libcurl/build-phone \
           libs/sqlite/build-mac libs/sqlite/build-phone
RUN rm -rf libs/libcurl/tarballs libs/sqlite/tarballs

# Build AltivecCocoa before sample apps so CURLmac can embed the Mac framework
# and CURLphone can statically link the phone archive and stage its fonts.
COPY libs/cocoa/   ./libs/cocoa/
RUN cd libs/cocoa && make all && make prune-intermediates

# Common mk fragments must land before the apps build below — each app's
# Makefile does `include /altivec/altivec_common_{mac,phone}.mk` by
# absolute path.
COPY altivec_common_app.mk   ./
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
    test -f libs/core/build-mac/lib/libAltivecCore.a; \
    test -f libs/core/build-phone/lib/libAltivecCore.a; \
    test -f libs/core/build-mac/lib/libAICURLConnection.a; \
    test -f libs/core/build-phone/lib/libAICURLConnection.a; \
    test ! -d libs/libcurl/build-mac; \
    test ! -d libs/libcurl/build-phone; \
    test ! -d libs/sqlite/build-mac; \
    test ! -d libs/sqlite/build-phone; \
    test ! -d libs/sqlite/tarballs; \
    test -f libs/core/build-phone/lib/cacert.pem; \
    test ! -d libs/core/build-phone/lib/AltivecCore.framework; \
    test -f libs/cocoa/build-phone/lib/libAltivecCocoa.a; \
    test -f libs/cocoa/build-phone/Resources/Fonts/FA7-Solid-900.otf; \
    test -f libs/cocoa/build-phone/Resources/Fonts/LICENSE-Font-Awesome.txt; \
    test ! -d libs/cocoa/build-phone/lib/AltivecCocoa.framework; \
    test -f apps/CURLphone/build-release/CURLphone.app/Fonts/FA7-Solid-900.otf; \
    test -f apps/CURLphone/build-release/CURLphone.app/Fonts/LICENSE-Font-Awesome.txt; \
    test ! -d apps/CURLphone/build-release/CURLphone.app/Frameworks

# Bake the rest of the runtime repo into /altivec/. Build-time-only files
# (Containerfile, compose.yml, docker/, .github/) are deliberately
# excluded. Kept after the apps build so edits to docs/README/
# templates do not invalidate the apps layer.
COPY AGENTS.md               ./
COPY README.md               ./
COPY LICENSE                 ./
COPY docs/                   ./docs/
COPY templates/              ./templates/

# Recreate the AGENTS.md aliases that AI agents look for by name.
RUN ln -sf AGENTS.md CLAUDE.md \
 && ln -sf AGENTS.md GEMINI.md
