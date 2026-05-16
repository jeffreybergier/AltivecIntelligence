FROM ubuntu:22.04 AS altivec-builder

# 1. Install Dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    # --- Core system / base ---
    bash \
    ca-certificates \
    xdg-utils \
    file \
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
    # --- CLI utilities / productivity ---
    jq \
    ripgrep \
    fd-find \
    tree \
    sqlite3 \
    # --- Image / icon tooling ---
    imagemagick \
    icnsutils \
    # --- macOS app bundle / packaging ---
    libplist-utils \
    # --- Reverse engineering / binary + protocol analysis ---
    xxd \
    binwalk \
    thrift-compiler \
    golang-go \
    mitmproxy \
    # --- Misc / extra tools ---
    wabt \
    && rm -rf /var/lib/apt/lists/*

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
COPY altivec_build/ ./altivec_build/

# 5. Build OSXCross and Compilers

RUN echo "Pre-Build: Altivec Intelligence" \
      && ./altivec_build/altivec_prebuild.sh

RUN echo "Build: osxcross" \
      && ./build.sh

RUN echo "Build: Apple GCC 4.2 (PPC)" \
      && POWERPC=1 ./build_gcc_ppc.sh \
      && rm -rf build
RUN echo "Build: Apple GCC 4.2 (i386 + x86_64)" \
      && ./build_gcc.sh \
      && rm -rf build

RUN echo "Post-Build: Altivec Intelligence" \
      && ./altivec_postbuild.sh \
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
      @google/gemini-cli \
      @earendil-works/pi-coding-agent \
      opencode-ai@latest \
      prettier \
      js-beautify \
      webcrack

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

# 9. Move into Working Directory
WORKDIR /repo/altivec
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["/bin/bash"]

