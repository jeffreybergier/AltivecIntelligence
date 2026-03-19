# --- Phase 1: Build OSXCross Toolchain ---
FROM ubuntu:22.04 AS altivec-base

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install Dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    llvm-dev \
    libxml2-dev \
    uuid-dev \
    libssl-dev \
    bash \
    patch \
    make \
    tar \
    xz-utils \
    bzip2 \
    gzip \
    git \
    python3 \
    python3-distutils \
    cpio \
    libz-dev \
    cmake \
    wget \
    rsync \
    ssh \
    zip \
    curl \
    jq \
    file \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    flex \
    bison \
    texinfo \
    m4 \
    ripgrep \
    fd-find \
    tree \
    iputils-ping \
    lldb \
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
ENV SDK_VERSION=10.6
ENV OSX_VERSION_MIN=10.5
ENV UNATTENDED=1
ENV INSTALLPREFIX=/osxcross/target
ENV OSXCROSS_FORCE_POWERPC_DSYMUTIL_INVOCATION=1
ENV LD_LIBRARY_PATH="/usr/lib/llvm-14/lib:${LD_LIBRARY_PATH}"

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


# RUN echo "Build: Clang 3.8" \
#       && ./build_clang.sh \
#       && rm -rf build

# TODO: Not Working Yet
# RUN echo "Build: LLVM dsymutil" \
#       && ./build_llvm_dsymutil.sh \
#       && rm -rf build

RUN echo "Post-Build: Altivec Intelligence" \
      && ./altivec_postbuild.sh \
      && rm -rf tarballs

# 5. Configure the final environment
ENV PATH="/osxcross/target/bin:${PATH}"

# 6. Move into Working Directory
WORKDIR /opt/osxcross
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/bin/bash"]

# --- Phase 2: Node.js and Gemini Environment ---
FROM altivec-base AS altivec-gemini
ENV FORCE_COLOR=1

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @google/gemini-cli

WORKDIR /opt/osxcross
ENTRYPOINT ["gemini"]
CMD ["--yolo"]

