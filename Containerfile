# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04 AS altivec-builder

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
    autotools-dev \
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
    zlib1g-dev \
    liblzma-dev \
    libbz2-dev \
    uuid-dev \
    # --- Build systems / scripting ---
    bc \
    cmake \
    python3 \
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
    radare2 \
    # --- Ruby / Jekyll static-site toolchain ---
    ruby-full \
    bundler \
    libffi-dev \
    # --- Document conversion ---
    pandoc \
    # --- Misc / extra tools ---
    wabt \
    && rm -rf /var/lib/apt/lists/*

ENV CURL_RETRY_FLAGS="--fail --silent --show-error --location --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 30"

# 2a. Settings for the User

# Use every CPU visible to the build container by default. Builds can be capped
# with `--build-arg JOBS=<count>` when memory or host responsiveness requires it.
ARG JOBS

# 2b. Set up environment

ENV ALTIVEC_MODERN_TOOLCHAIN=/osxcross/modern \
    ALTIVEC_LEGACY_TOOLCHAIN=/osxcross/legacy/target \
    OSXCROSS_NO_DSYMUTIL=1

# Host bind mounts often carry the macOS UID/GID, so Git running as root inside
# the container otherwise rejects them as dubious ownership.
RUN git config --system --add safe.directory "*"

# 3. Build the isolated Apple GCC 4.2 / PowerPC toolchain. This deliberately
# remains on OSXCross ppc-test and installs under /osxcross/legacy/target.
# Keeping it before the current OSXCross build means modern-toolchain changes
# do not invalidate the expensive Apple GCC layers.
WORKDIR /osxcross/legacy
COPY --chmod=0755 docker/prebuild.sh docker/postbuild.sh ./docker/
COPY docker/patches/ ./docker/patches/

# Keep SDK/GCC source tarballs out of committed image layers. They are large,
# and leaving them in an early layer can make the final image export fail even
# when a later layer deletes /osxcross/tarballs.

RUN --mount=type=cache,id=altivec-legacy-tarballs,target=/osxcross/legacy/tarballs,sharing=locked \
    echo "Prepare: legacy OSXCross" \
      && ./docker/prebuild.sh

RUN --mount=type=cache,id=altivec-legacy-tarballs,target=/osxcross/legacy/tarballs,sharing=locked \
    echo "Build: legacy OSXCross" \
      && SDK_VERSION=10.5 OSX_VERSION_MIN=10.5 UNATTENDED=1 \
         JOBS="${JOBS:-$(nproc)}" ./build.sh

RUN --mount=type=cache,id=altivec-legacy-tarballs,target=/osxcross/legacy/tarballs,sharing=locked \
    echo "Build: Apple GCC 4.2 (PPC)" \
      && GCC_VERSION=4.2.1 APPLE_GCC=1 JOBS="${JOBS:-$(nproc)}" \
         POWERPC=1 ./build_gcc_ppc.sh \
      && rm -rf build
RUN --mount=type=cache,id=altivec-legacy-tarballs,target=/osxcross/legacy/tarballs,sharing=locked \
    echo "Build: Apple GCC 4.2 (i386 + x86_64)" \
      && GCC_VERSION=4.2.1 APPLE_GCC=1 JOBS="${JOBS:-$(nproc)}" \
         ./build_gcc.sh \
      && rm -rf build

# 4. Build current OSXCross as the primary macOS foundation. The stable flavor
# uses current cctools/ld64 while retaining i386-capable Apple tooling.
WORKDIR /osxcross/modern-source
COPY --chmod=0755 docker/prebuild-modern.sh docker/postbuild-modern.sh ./docker/

RUN --mount=type=cache,id=altivec-modern-tarballs,target=/osxcross/modern-source/tarballs,sharing=locked \
    ./docker/prebuild-modern.sh

RUN --mount=type=cache,id=altivec-modern-tarballs,target=/osxcross/modern-source/tarballs,sharing=locked \
    echo "Build: current OSXCross (stable)" \
      && TARGET_DIR=/osxcross/modern SDK_VERSION=11.3 OSX_VERSION_MIN=10.9 \
         ENABLE_ARCHS="x86_64 arm64" BUILD_FLAVOR=stable UNATTENDED=1 \
         JOBS="${JOBS:-$(nproc)}" ./build.sh

RUN --mount=type=cache,id=altivec-modern-tarballs,target=/osxcross/modern-source/tarballs,sharing=locked \
    ./docker/postbuild-modern.sh /osxcross/modern-source /osxcross/modern \
    && ln -s /osxcross/modern /osxcross/target

COPY --chmod=0755 docker/toolchain-smoke.sh /osxcross/legacy/docker/toolchain-smoke.sh
COPY docker/fixtures/ /osxcross/legacy/docker/fixtures/
RUN bash /osxcross/legacy/docker/toolchain-smoke.sh

# 5. Keep native Linux tools ahead of OSXCross by default. Ruby/Bundler and
# other host-native extension builds may invoke tools like `ld` indirectly
# through GCC and do not always honor LD=/usr/bin/ld. Altivec makefiles invoke
# osxcross compilers/linkers explicitly, or prepend /osxcross/target/bin only
# for the commands that need it.
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/altivec/bin:/osxcross/modern/bin:/osxcross/legacy/target/bin" \
    CC=/usr/bin/gcc \
    CXX=/usr/bin/g++ \
    LD=/usr/bin/ld \
    AR=/usr/bin/ar

# 7. Node.js 24 LTS (matches wrangler's supported runtime). Pin and verify the
# NodeSource package itself: repository metadata signatures occasionally fail
# under Docker Desktop even though the package and its checksums are valid.
ARG TARGETARCH
ARG NODE_VERSION=24.19.0
RUN case "${TARGETARCH}" in \
      amd64) NODE_SHA256=132518334c7b6a30cb77731ecd2951d59b7714d18f8e3ce6d970323b561a272d ;; \
      arm64) NODE_SHA256=46bf2bf76991c7e1e9a2b7ceb5b232e516103ced363bcb2e0f16c740873fc2f7 ;; \
      *) echo "Unsupported Node.js architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl $CURL_RETRY_FLAGS -o /tmp/nodejs.deb \
      "https://deb.nodesource.com/node_24.x/pool/main/n/nodejs/nodejs_${NODE_VERSION}-1nodesource1_${TARGETARCH}.deb" \
    && echo "${NODE_SHA256}  /tmp/nodejs.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends /tmp/nodejs.deb \
    && rm -f /tmp/nodejs.deb \
    && rm -rf /var/lib/apt/lists/*

# 8a. Pin npm independently of the NodeSource package, then install globals
RUN curl $CURL_RETRY_FLAGS -o /tmp/npm.tgz \
      https://registry.npmjs.org/npm/-/npm-12.0.2.tgz \
    && mkdir -p /tmp/npm-install \
    && tar xzf /tmp/npm.tgz -C /tmp/npm-install \
    && node /tmp/npm-install/package/bin/npm-cli.js install -g npm@12.0.2 \
    && rm -rf /tmp/npm.tgz /tmp/npm-install

# This development image intentionally installs the latest CLI releases, so
# allow their install-time lifecycle scripts and verify the results below.

COPY --chmod=0644 docker/npm-tool-smoke.mjs /usr/local/lib/altivec/npm-tool-smoke.mjs

RUN npm install -g \
      --dangerously-allow-all-scripts \
      wrangler \
      jsdom \
      qrcode-terminal \
      @anthropic-ai/claude-code \
      @openai/codex \
      @earendil-works/pi-coding-agent \
      @moonshot-ai/kimi-code \
      opencode-ai@latest \
      prettier \
      js-beautify \
      webcrack

RUN node /usr/local/lib/altivec/npm-tool-smoke.mjs

# 8b. Headless browser testing and MCP browser control. Keep Playwright in a
#     separate layer so updating it does not reinstall every global npm tool.
ARG PLAYWRIGHT_VERSION=1.62.1
ARG PLAYWRIGHT_MCP_VERSION=0.0.78
ENV NODE_PATH=/usr/lib/node_modules \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers \
    PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/local/bin/playwright-chromium \
    PLAYWRIGHT_MCP_HEADLESS=true \
    PLAYWRIGHT_MCP_ISOLATED=true \
    PLAYWRIGHT_MCP_NO_SANDBOX=true \
    PLAYWRIGHT_MCP_OUTPUT_DIR=/cache/playwright-mcp

RUN npm install -g \
      --dangerously-allow-all-scripts \
      "@playwright/test@${PLAYWRIGHT_VERSION}" \
      "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"

# These are the only Chromium runtime libraries not already supplied by the
# base tool set. Install pinned Ubuntu packages directly because a second apt
# metadata refresh is unreliable under Docker Desktop (see the Node stage).
RUN case "${TARGETARCH}" in \
      amd64) \
        UBUNTU_ARCHIVE=https://archive.ubuntu.com/ubuntu; \
        NSPR_SHA256=e579e72d091f6c7a13f5a756c31065b15aae5b81840d61b069355aa2283c07b4; \
        NSS_SHA256=4254f11d782dfb970e78113519a59d440112ed43c4b56f709da0aef81da8651a ;; \
      arm64) \
        UBUNTU_ARCHIVE=https://ports.ubuntu.com/ubuntu-ports; \
        NSPR_SHA256=0bd5994126c41aa05aa380954a3cb2ae56a0a8ebe368a0e01a411fdcc0cb9c68; \
        NSS_SHA256=daf32de5e12139aa84fde7a3e2784d5d7277259e22f14affcd82d81545b5312e ;; \
      *) echo "Unsupported Playwright architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl $CURL_RETRY_FLAGS -o /tmp/libnspr4.deb \
      "${UBUNTU_ARCHIVE}/pool/main/n/nspr/libnspr4_4.35-1.1build1_${TARGETARCH}.deb" \
    && curl $CURL_RETRY_FLAGS -o /tmp/libnss3.deb \
      "${UBUNTU_ARCHIVE}/pool/main/n/nss/libnss3_3.98-1ubuntu0.2_${TARGETARCH}.deb" \
    && printf '%s  %s\n%s  %s\n' \
      "${NSPR_SHA256}" /tmp/libnspr4.deb \
      "${NSS_SHA256}" /tmp/libnss3.deb \
      | sha256sum -c - \
    && apt-get install -y --no-install-recommends \
      /tmp/libnspr4.deb /tmp/libnss3.deb \
    && rm -f /tmp/libnspr4.deb /tmp/libnss3.deb

# Install only Chromium, rather than Playwright's full three-browser matrix.
# MCP follows its own Playwright prerelease, so point it at the stable test
# runner's managed Chromium instead of downloading a duplicate revision.
# The image runs as root, which requires Chromium's sandbox to be disabled;
# MCP remains headless and uses an isolated in-memory profile by default.
RUN set -eux; \
    playwright install --no-progress chromium; \
    PLAYWRIGHT_CHROMIUM_PATH="$( \
      NODE_PATH="$(npm root -g)" \
      node -e 'process.stdout.write(require("@playwright/test").chromium.executablePath())' \
    )"; \
    test -x "${PLAYWRIGHT_CHROMIUM_PATH}"; \
    ln -s "${PLAYWRIGHT_CHROMIUM_PATH}" /usr/local/bin/playwright-chromium; \
    NODE_PATH="$(npm root -g)" node -e \
      'const { chromium } = require("@playwright/test"); (async () => { const browser = await chromium.launch({ headless: true }); const page = await browser.newPage(); await page.setContent("<!doctype html><title>playwright-smoke</title>"); if (await page.title() !== "playwright-smoke") throw new Error("Chromium smoke test failed"); await browser.close(); })().catch(error => { console.error(error); process.exit(1); });'; \
    playwright --version; \
    playwright-mcp --version; \
    rm -rf /var/lib/apt/lists/*

# 8c. Antigravity CLI (Google's replacement for Gemini CLI)
RUN curl $CURL_RETRY_FLAGS -o /tmp/antigravity-install.sh \
      https://antigravity.google/cli/install.sh \
    && bash /tmp/antigravity-install.sh --dir /usr/local/bin \
    && rm -f /tmp/antigravity-install.sh

# 9a. rcodesign — real Apple code signer (osxcross only ships
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

# 9b. ldid — pseudo-signer + entitlements editor for jailbroken iOS.
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

# 9c. ipsw — blacktop's Mach-O analysis multi-tool. `ipsw class-dump`
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

# 9d. actionlint — Ubuntu 24.04 does not package it, so install the verified
#     upstream binary for each image architecture. Keep this behind the
#     heavyweight toolchain layers so version bumps preserve their cache.
ARG ACTIONLINT_VERSION=1.7.12
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) \
        ACTIONLINT_ARCH=amd64; \
        ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 \
        ;; \
      arm64) \
        ACTIONLINT_ARCH=arm64; \
        ACTIONLINT_SHA256=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 \
        ;; \
      *) echo "unsupported architecture for actionlint" >&2; exit 1 ;; \
    esac; \
    ACTIONLINT_ARCHIVE="actionlint_${ACTIONLINT_VERSION}_linux_${ACTIONLINT_ARCH}.tar.gz"; \
    curl $CURL_RETRY_FLAGS -o "/tmp/${ACTIONLINT_ARCHIVE}" \
      "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${ACTIONLINT_ARCHIVE}"; \
    echo "${ACTIONLINT_SHA256}  /tmp/${ACTIONLINT_ARCHIVE}" | sha256sum -c -; \
    mkdir -p /tmp/actionlint-install; \
    tar -xzf "/tmp/${ACTIONLINT_ARCHIVE}" -C /tmp/actionlint-install; \
    install -m 0755 /tmp/actionlint-install/actionlint /usr/local/bin/actionlint; \
    rm -rf "/tmp/${ACTIONLINT_ARCHIVE}" /tmp/actionlint-install; \
    actionlint -version

# 10. Working Directory & Runtime
WORKDIR /repo/altivec
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["/bin/bash"]

# /altivec/bin is already on PATH above so altivec-deploy, altivec-release, and
# altivec-chooser are callable by bare name (no ./ prefix, no .sh extension).
# That PATH lives in the base stage so the dev compose (which bind-mounts the
# repo at /altivec and targets altivec-builder) gets the same PATH as the
# prebuilt GHCR image — the bind-mount supplies the files at runtime.

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
COPY --chmod=0644 altivec_toolchains.mk /altivec/altivec_toolchains.mk
RUN chmod +x /altivec/bin/* \
 && altivec-release --help >/dev/null

# Clang automatically force-loads this path for pre-iOS-5 ARC links. Use the
# Apple archive shipped by Xcode 6.4: it supports armv7/iOS 4.3 and predates
# the objc_loadClassref dependency in modern Xcode's replacement archive.
# Keep this stable input late in the builder stage so changing it does not
# invalidate the unrelated OSXCross, Node, and native-tool installation layers.
COPY --chmod=0644 toolchain/iOS/armv7/payload/lib/arc/libarclite_iphoneos.a /opt/altivec/lib/arc/libarclite_iphoneos.a
RUN set -eux; \
    echo 'f019ba9bf87bb7a47cfd063542d9e6ed81efe76472c869ad509230aafef18bf8  /opt/altivec/lib/arc/libarclite_iphoneos.a' \
      | sha256sum -c -; \
    clang_bin="$(readlink -f "$(command -v clang)")"; \
    clang_arc_dir="$(dirname "$(dirname "$clang_bin")")/lib/arc"; \
    mkdir -p "$clang_arc_dir"; \
    ln -s /opt/altivec/lib/arc/libarclite_iphoneos.a \
      "$clang_arc_dir/libarclite_iphoneos.a"; \
    /osxcross/modern/bin/lipo \
      /opt/altivec/lib/arc/libarclite_iphoneos.a \
      -verify_arch armv7; \
    strings /opt/altivec/lib/arc/libarclite_iphoneos.a \
      | grep -Fq -- '-miphoneos-version-min=4.3'; \
    /osxcross/modern/bin/nm /opt/altivec/lib/arc/libarclite_iphoneos.a \
      | grep -Fq '_OBJC_METACLASS_$___ARCLite__'; \
    if /osxcross/modern/bin/nm \
        /opt/altivec/lib/arc/libarclite_iphoneos.a \
        | grep -Eq '[[:space:]]_objc_loadClassref$'; then \
      echo 'error: ARCLite requires objc_loadClassref from a newer SDK' >&2; \
      exit 1; \
    fi

# 11. GHCR image layer — bakes the Altivec runtime repo into /altivec/.
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

# Build AltivecCocoa after Core. The separately run release-extras workflow
# uses these exact image outputs to build and package the sample applications.
COPY libs/cocoa/   ./libs/cocoa/
RUN cd libs/cocoa && make all && make prune-intermediates

# Ship common make fragments and sample source, but do not compile the samples
# into the image. Each app includes the fragments from /altivec by absolute
# path. Tagged sample binaries are release assets built from this image.
COPY altivec_common_app.mk   ./
COPY altivec_common_mac.mk   ./
COPY altivec_common_phone.mk ./
COPY apps/                   ./apps/

# Validate the retained library layout and sample build rules. Compile the
# smallest phone sample here so the production fat-build path and deployment
# targets are checked before the image is published; the remaining real sample
# builds are deferred to release extras.
RUN set -e; \
    test -f libs/core/build-mac/lib/libAltivecCore.a; \
    test -f libs/core/build-phone/lib/libAltivecCore.a; \
    test -f apps/CURLmac/AICURLConnection.m; \
    test -f apps/CURLphone/AICURLConnection.m; \
    test ! -e libs/core/build-mac/lib/libAICURLConnection.a; \
    test ! -e libs/core/build-phone/lib/libAICURLConnection.a; \
    test ! -e libs/core/build-mac/include/AICURLConnection.h; \
    test ! -e libs/core/build-phone/include/AICURLConnection.h; \
    test ! -e libs/core/build-mac/lib/AltivecCore.framework/Headers/AICURLConnection.h; \
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
    test -z "$(find apps -type d -name 'build-*' -print -quit)"; \
    for app in SingleWindow SingleScreen CURLmac CURLphone; do \
      make -C "apps/$app" -n release ALTIVEC_ROOT=/altivec >/dev/null; \
    done; \
    make -C apps/SingleScreen release ALTIVEC_ROOT=/altivec; \
    phone_bin=apps/SingleScreen/build-release/SingleScreen.app/SingleScreen; \
    /osxcross/modern/bin/lipo "$phone_bin" -verify_arch armv7 arm64; \
    for arch_and_version in armv7:4.3 arm64:7.0; do \
      arch="${arch_and_version%%:*}"; \
      expected="${arch_and_version##*:}"; \
      thin="/tmp/singlescreen-$arch"; \
      /osxcross/modern/bin/lipo "$phone_bin" -thin "$arch" -output "$thin"; \
      actual="$(/osxcross/modern/bin/otool -l "$thin" | awk \
        '$1 == "cmd" && ($2 == "LC_VERSION_MIN_IPHONEOS" || \
                         $2 == "LC_BUILD_VERSION") { found = 1; next } \
         found && ($1 == "version" || $1 == "minos") { print $2; exit }')"; \
      test "$actual" = "$expected" || { \
        echo "error: $arch minimum is $actual; expected $expected" >&2; \
        exit 1; \
      }; \
      rm -f "$thin"; \
    done; \
    make -C apps/SingleScreen clean ALTIVEC_ROOT=/altivec; \
    test -z "$(find apps/SingleScreen -type d -name 'build-*' -print -quit)"; \
    make -C apps/CURLphone -Bn release ALTIVEC_ROOT=/altivec \
      PHONE_SOURCE_FLAGS=-fobjc-arc \
      > /tmp/curlphone-arc-link-plan; \
    awk '/Linking Phone universal/ { in_link = 1 }; \
         in_link && /-Xarch_armv7 -fobjc-arc/ { found = 1 }; \
         END { exit(found ? 0 : 1) }' \
      /tmp/curlphone-arc-link-plan; \
    rm -f /tmp/curlphone-arc-link-plan

# Bake the rest of the runtime repo into /altivec/. Build-time-only files
# (Containerfile, compose.yml, docker/, .github/) are deliberately
# excluded. Kept after the runtime source so edits to docs/README/templates do
# not invalidate the library layers.
COPY AGENTS.md               ./
COPY README.md               ./
COPY LICENSE                 ./
COPY docs/                   ./docs/
COPY templates/              ./templates/

# Recreate the AGENTS.md aliases that AI agents look for by name.
RUN ln -sf AGENTS.md CLAUDE.md \
 && ln -sf AGENTS.md GEMINI.md
