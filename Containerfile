# syntax=docker/dockerfile:1.7
FROM ubuntu:26.04 AS altivec-builder

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
    # GCC 14's C++ library preserves the unchecked behavior expected by the
    # legacy ld64 sources; Ubuntu 26's default GCC 15 enables bounds assertions.
    g++-14 \
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
    # --- Headless browser runtime ---
    libnspr4 \
    libnss3 \
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
    handbrake-cli \
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

# 3. Keep native Linux tools ahead of OSXCross by default. Ruby/Bundler and
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

# 9d. actionlint — Ubuntu 26.04 does not package it, so install the verified
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

# /altivec/bin is already on PATH above, so runtime commands are callable by
# bare name without a .sh extension.

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

# Copy only inputs that can affect the SDK-dependent build before its expensive
# RUN. Documentation and unrelated runtime helpers remain in later layers.
COPY --chmod=0755 bin/altivec-sdk /altivec/bin/altivec-sdk
COPY share/                   /altivec/share/
COPY altivec_toolchains.mk    /altivec/
COPY altivec_common_app.mk    /altivec/
COPY altivec_common_mac.mk    /altivec/
COPY altivec_common_phone.mk  /altivec/
COPY libs/                    /altivec/libs/
COPY apps/                    /altivec/apps/

RUN mkdir -p /altivec-sdk /build-sdk-dependent \
 && altivec-sdk --help >/dev/null

# This is the only image instruction allowed to see Apple SDK archives. The
# large, read-only `altivec_sdk` build context is mounted without being copied
# into a layer. Bind only the five Docker inputs consumed by this step so its
# dependency boundary stays explicit as more Docker helpers are added. The mega
# script builds everything and purges installed SDKs before the layer is
# committed.
RUN --mount=type=bind,from=altivec_sdk,source=.,target=/altivec-sdk,readonly \
    --mount=type=bind,source=docker/build-sdk-dependent.sh,target=/build-sdk-dependent/build-sdk-dependent.sh,readonly \
    --mount=type=bind,source=docker/toolchain-smoke.c,target=/build-sdk-dependent/toolchain-smoke.c,readonly \
    --mount=type=bind,source=docker/osxcross-build-gcc-intel.patch,target=/build-sdk-dependent/osxcross-build-gcc-intel.patch,readonly \
    --mount=type=bind,source=docker/osxcross-build-gcc-ppc.patch,target=/build-sdk-dependent/osxcross-build-gcc-ppc.patch,readonly \
    --mount=type=bind,source=docker/osxcross-build-host-gcc14.patch,target=/build-sdk-dependent/osxcross-build-host-gcc14.patch,readonly \
    --mount=type=cache,id=altivec-libcurl-tarballs,target=/altivec/libs/libcurl/tarballs,sharing=locked \
    --mount=type=cache,id=altivec-sqlite-tarballs,target=/altivec/libs/sqlite/tarballs,sharing=locked \
    --mount=type=cache,id=altivec-fontawesome-files,target=/altivec/libs/cocoa/tarballs,sharing=locked \
    ALTIVEC_SDK_ARCHIVE_DIR=/altivec-sdk \
      /build-sdk-dependent/build-sdk-dependent.sh

# The cache mounts above hide the source-tree dependency caches while the mega
# script runs. Remove their restored image-layer contents and independently
# verify the SDK-free runtime after the build-context mounts have disappeared.
RUN rm -rf /altivec/libs/libcurl/tarballs /altivec/libs/sqlite/tarballs \
           /altivec/libs/cocoa/tarballs \
 && altivec-sdk audit /osxcross \
 && altivec-sdk audit /altivec \
 && altivec-sdk audit /opt \
 && altivec-sdk audit /usr/local

COPY bin/                     /altivec/bin/
COPY AGENTS.md README.md LICENSE /altivec/
COPY docs/                    /altivec/docs/
COPY templates/               /altivec/templates/

RUN chmod +x /altivec/bin/* \
 && altivec-release --help >/dev/null \
 && altivec-sdk --help >/dev/null \
 && ln -sf AGENTS.md /altivec/CLAUDE.md \
 && ln -sf AGENTS.md /altivec/GEMINI.md \
 && altivec-sdk audit /altivec

FROM altivec-builder AS ghcr-action
WORKDIR /altivec
