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

# 3. Copy OSXCross and build base toolchain
WORKDIR /osxcross
COPY altivec_build/ ./altivec_build/

# 4. Build OSXCross and Compilers

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

# 5. Configure the final environment
ENV PATH="/osxcross/target/bin:${PATH}"

# 6. Node.js 22 LTS (matches wrangler's supported runtime)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# 7. Cloudflare CLI + local dev deps needed to compute / test X-Hmac
RUN npm install -g \
      wrangler \
      jsdom \
      qrcode-terminal \
      @anthropic-ai/claude-code \
      @openai/codex \
      @google/gemini-cli

# 8. Move into Working Directory
WORKDIR /repo/altivec
ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["/bin/bash"]

