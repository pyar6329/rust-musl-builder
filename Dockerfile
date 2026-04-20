# syntax=docker/dockerfile:1
FROM ubuntu:24.04

# The OpenSSL version to use. Here is the place to check for new releases:
#
# - https://www.openssl.org/source/
#
# ALSO UPDATE hooks/build!
ARG OPENSSL_VERSION=3.3.0

# Versions for other dependencies. Here are the places to check for new
# releases:
#
# - https://github.com/rust-lang/mdBook/releases
# - https://github.com/EmbarkStudios/cargo-about/releases
# - https://github.com/EmbarkStudios/cargo-deny/releases
# - http://zlib.net/
# - https://ftp.postgresql.org/pub/source/
ARG CARGO_ABOUT_VERSION=0.6.0
ARG CARGO_DENY_VERSION=0.14.16
ARG ZLIB_VERSION=1.3.2
ARG POSTGRESQL_VERSION=18.3
ARG PROTOBUF_VERSION=26.1

# Make sure we have basic dev tools for building C libraries.  Our goal here is
# to support the musl-libc builds and Cargo builds needed for a large selection
# of the most popular crates.
#
# We also set up a `rust` user by default. This user has sudo privileges if you
# need to install any more software.
#
# `mdbook` is the standard Rust tool for making searchable HTML manuals.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/downloads,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    buildDeps='unzip' && \
    apt-get update && \
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -yq \
    $buildDeps \
    build-essential \
    cmake \
    curl \
    file \
    git \
    graphviz \
    musl-dev \
    musl-tools \
    libpq-dev \
    libsqlite-dev \
    libssl-dev \
    linux-libc-dev \
    pkgconf \
    sudo \
    xutils-dev \
    flex \
    bison \
    && \
    (userdel -r ubuntu 2>/dev/null || true) && \
    useradd rust --user-group --create-home --shell /bin/bash --groups sudo && \
    T="/downloads/cargo-about-$CARGO_ABOUT_VERSION-x86_64-unknown-linux-musl.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/EmbarkStudios/cargo-about/releases/download/$CARGO_ABOUT_VERSION/cargo-about-$CARGO_ABOUT_VERSION-x86_64-unknown-linux-musl.tar.gz" && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-about-$CARGO_ABOUT_VERSION-x86_64-unknown-linux-musl/cargo-about" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-about-$CARGO_ABOUT_VERSION-x86_64-unknown-linux-musl" && \
    T="/downloads/cargo-deny-$CARGO_DENY_VERSION-x86_64-unknown-linux-musl.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/EmbarkStudios/cargo-deny/releases/download/$CARGO_DENY_VERSION/cargo-deny-$CARGO_DENY_VERSION-x86_64-unknown-linux-musl.tar.gz" && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-deny-$CARGO_DENY_VERSION-x86_64-unknown-linux-musl/cargo-deny" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-deny-$CARGO_DENY_VERSION-x86_64-unknown-linux-musl" && \
    T="/downloads/protoc-$PROTOBUF_VERSION-linux-x86_64.zip" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOBUF_VERSION/protoc-$PROTOBUF_VERSION-linux-x86_64.zip" && \
    unzip -o -d /usr/local "$T" && \
    apt-get purge -y --auto-remove $buildDeps

# Static linking for C++ code
RUN ln -s "/usr/bin/g++" "/usr/bin/musl-g++"

# Build a static library version of OpenSSL using musl-libc.  This is needed by
# the popular Rust `hyper` crate.
#
# We point /usr/local/musl/include/linux at some Linux kernel headers (not
# necessarily the right ones) in an effort to compile OpenSSL 3.2's "engine"
# component. It's possible that this will cause bizarre and terrible things to
# happen. There may be "sanitized" header
RUN --mount=type=cache,target=/downloads,sharing=locked \
    echo "Building OpenSSL" && \
    ls /usr/include/linux && \
    mkdir -p /usr/local/musl/include && \
    ln -s /usr/include/linux /usr/local/musl/include/linux && \
    ln -s /usr/include/x86_64-linux-gnu/asm /usr/local/musl/include/asm && \
    ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic && \
    T="/downloads/openssl-$OPENSSL_VERSION.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "openssl-$OPENSSL_VERSION" && \
    env CC=musl-gcc ./Configure no-shared no-zlib -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY linux-x86_64 && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make -j"$(nproc)" depend && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make -j"$(nproc)" && \
    make install && \
    rm /usr/local/musl/include/linux /usr/local/musl/include/asm /usr/local/musl/include/asm-generic && \
    rm -rf "/tmp/openssl-$OPENSSL_VERSION"

RUN --mount=type=cache,target=/downloads,sharing=locked \
    echo "Building zlib" && \
    T="/downloads/zlib-$ZLIB_VERSION.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "http://zlib.net/zlib-$ZLIB_VERSION.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "zlib-$ZLIB_VERSION" && \
    CC=musl-gcc ./configure --static --prefix=/usr/local/musl && \
    make -j"$(nproc)" && make install && \
    rm -rf "/tmp/zlib-$ZLIB_VERSION"

RUN --mount=type=cache,target=/downloads,sharing=locked \
    echo "Building libpq" && \
    T="/downloads/postgresql-$POSTGRESQL_VERSION.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://ftp.postgresql.org/pub/source/v$POSTGRESQL_VERSION/postgresql-$POSTGRESQL_VERSION.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "postgresql-$POSTGRESQL_VERSION" && \
    CC=musl-gcc CPPFLAGS="-I/usr/local/musl/include" LDFLAGS="-L/usr/local/musl/lib -L/usr/local/musl/lib64" ./configure --with-openssl --without-readline --without-icu --without-zstd --without-lz4 --prefix=/usr/local/musl && \
    cd src/interfaces/libpq && make -j"$(nproc)" all-static-lib && make install-lib-static && \
    cd ../../bin/pg_config && make -j"$(nproc)" && make install && \
    cd "/tmp/postgresql-$POSTGRESQL_VERSION/src" && \
    make -j"$(nproc)" -C common && \
    make -j"$(nproc)" -C backend && \
    make -j"$(nproc)" -C interfaces/libpq && \
    make -C interfaces/libpq install-strip && \
    make -j"$(nproc)" -C include && \
    make -C include install-strip && \
    make -j"$(nproc)" -C bin/pg_config && \
    make -C bin/pg_config install-strip && \
    mkdir libpq-tmp && \
    cd libpq-tmp && \
    ar -x ../interfaces/libpq/libpq.a && \
    ar -x ../common/libpgcommon.a && \
    ar -x ../port/libpgport.a && \
    rm -rf /usr/local/musl/lib/libpq.a && \
    ar -qs /usr/local/musl/lib/libpq.a ./*.o && \
    strip -x /usr/local/musl/lib/libpq.a && \
    rm -rf "/tmp/postgresql-$POSTGRESQL_VERSION"

# (Please feel free to submit pull requests for musl-libc builds of other C
# libraries needed by the most popular and common Rust crates, to avoid
# everybody needing to build them manually.)

# Install a `git credentials` helper for using GH_USER and GH_TOKEN to access
# private repositories if desired. We make sure this is configured for root,
# here, and for the `rust` user below.
COPY git-credential-ghtoken /usr/local/bin/ghtoken
RUN git config --global credential.https://github.com.helper ghtoken

# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
#
# We use the instructions at https://github.com/rust-lang/rustup/issues/2383
# to install the rustup toolchain as root.
ENV RUSTUP_HOME=/opt/rust/rustup \
    PATH=/home/rust/.cargo/bin:/opt/rust/cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CARGO_HOME=/opt/rust/cargo

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=stable

# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain $TOOLCHAIN --profile minimal --no-modify-path && \
    rustup component add rustfmt && \
    rustup component add clippy && \
    rustup target add x86_64-unknown-linux-musl && \
    rustup component add llvm-tools-preview
COPY cargo-config.toml /opt/rust/cargo/config.toml

# Set up our environment variables so that we cross-compile using musl-libc by
# default.
ENV X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    LIBZ_SYS_STATIC=1 \
    TARGET=musl

# Install some useful Rust tools from source. This will use the static linking
# toolchain, but that should be OK.
#
# We include cargo-audit for compatibility with earlier versions of this image,
# but cargo-deny provides a superset of cargo-audit's features.
RUN --mount=type=cache,target=/opt/rust/cargo/registry,sharing=locked \
    --mount=type=cache,target=/opt/rust/cargo/git,sharing=locked \
    cargo install -f cargo-audit && \
    cargo install -f cargo-deb && \
    cargo install -f cargo-llvm-cov

# Allow sudo without a password.
COPY --chmod=440 sudoers /etc/sudoers.d/nopasswd

# Run all further code as user `rust`, create our working directories, install
# our config file, and set up our credential helper.
#
# You should be able to switch back to `USER root` from another `Dockerfile`
# using this image if you need to do so.
USER rust
RUN mkdir -p /home/rust/libs /home/rust/src /home/rust/.cargo && \
    ln -s /opt/rust/cargo/config.toml /home/rust/.cargo/config.toml && \
    git config --global credential.https://github.com.helper ghtoken

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /home/rust/src
