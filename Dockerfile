# syntax=docker/dockerfile:1

# ==========================================================================
# Versions
# ==========================================================================
ARG OPENSSL_VERSION=3.3.0
ARG ZLIB_VERSION=1.3.2
ARG POSTGRESQL_VERSION=18.3
ARG CARGO_ABOUT_VERSION=0.6.0
ARG CARGO_DENY_VERSION=0.14.16
ARG PROTOBUF_VERSION=26.1

# ==========================================================================
# base: tools shared across builder stages
# ==========================================================================
FROM ubuntu:24.04 AS base
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq \
      bison \
      build-essential \
      ca-certificates \
      curl \
      flex \
      linux-libc-dev \
      musl-dev \
      musl-tools \
      perl \
      pkgconf

# ==========================================================================
# openssl-builder: static OpenSSL against musl
# ==========================================================================
FROM base AS openssl-builder
ARG OPENSSL_VERSION
RUN --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    mkdir -p /usr/local/musl/include && \
    ln -s /usr/include/linux /usr/local/musl/include/linux && \
    ln -s /usr/include/x86_64-linux-gnu/asm /usr/local/musl/include/asm && \
    ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic && \
    T="/downloads/openssl-${OPENSSL_VERSION}.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "openssl-${OPENSSL_VERSION}" && \
    env CC=musl-gcc ./Configure no-shared no-zlib -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY linux-x86_64 && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make -j"$(nproc)" depend && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make -j"$(nproc)" && \
    make install_sw && \
    rm /usr/local/musl/include/linux /usr/local/musl/include/asm /usr/local/musl/include/asm-generic

# ==========================================================================
# zlib-builder: static zlib against musl
# ==========================================================================
FROM base AS zlib-builder
ARG ZLIB_VERSION
RUN --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    T="/downloads/zlib-${ZLIB_VERSION}.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "zlib-${ZLIB_VERSION}" && \
    CC=musl-gcc ./configure --static --prefix=/usr/local/musl && \
    make -j"$(nproc)" && make install

# ==========================================================================
# libpq-builder: static libpq against musl (needs OpenSSL)
# ==========================================================================
FROM base AS libpq-builder
ARG POSTGRESQL_VERSION
COPY --from=openssl-builder /usr/local/musl /usr/local/musl
RUN --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    T="/downloads/postgresql-${POSTGRESQL_VERSION}.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://ftp.postgresql.org/pub/source/v${POSTGRESQL_VERSION}/postgresql-${POSTGRESQL_VERSION}.tar.gz" && \
    cd /tmp && tar xzf "$T" && cd "postgresql-${POSTGRESQL_VERSION}" && \
    CC=musl-gcc \
    CPPFLAGS="-I/usr/local/musl/include" \
    LDFLAGS="-L/usr/local/musl/lib -L/usr/local/musl/lib64" \
    ./configure --with-openssl --without-readline --without-icu --without-zstd --without-lz4 --prefix=/usr/local/musl && \
    cd src/interfaces/libpq && make -j"$(nproc)" all-static-lib && make install-lib-static && \
    cd ../../bin/pg_config && make -j"$(nproc)" && make install && \
    cd "/tmp/postgresql-${POSTGRESQL_VERSION}/src" && \
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
    strip -x /usr/local/musl/lib/libpq.a

# ==========================================================================
# final: user-facing image with Rust toolchain + pre-built static libs
# ==========================================================================
FROM ubuntu:24.04 AS final
ARG CARGO_ABOUT_VERSION
ARG CARGO_DENY_VERSION
ARG PROTOBUF_VERSION

# Runtime deps, extra tools, pre-built binary downloads (cargo-about, cargo-deny, protoc)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    buildDeps='unzip' && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq \
      $buildDeps \
      bison \
      build-essential \
      cmake \
      curl \
      file \
      flex \
      git \
      graphviz \
      libpq-dev \
      libsqlite3-dev \
      libssl-dev \
      linux-libc-dev \
      musl-dev \
      musl-tools \
      pkgconf \
      sudo \
      xutils-dev && \
    (userdel -r ubuntu 2>/dev/null || true) && \
    useradd rust --user-group --create-home --shell /bin/bash --groups sudo && \
    T="/downloads/cargo-about-${CARGO_ABOUT_VERSION}-x86_64-unknown-linux-musl.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/EmbarkStudios/cargo-about/releases/download/${CARGO_ABOUT_VERSION}/cargo-about-${CARGO_ABOUT_VERSION}-x86_64-unknown-linux-musl.tar.gz" && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-about-${CARGO_ABOUT_VERSION}-x86_64-unknown-linux-musl/cargo-about" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-about-${CARGO_ABOUT_VERSION}-x86_64-unknown-linux-musl" && \
    T="/downloads/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl/cargo-deny" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl" && \
    T="/downloads/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip" && \
    [ -f "$T" ] || curl -fL --retry 3 -o "$T" "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-x86_64.zip" && \
    unzip -o -d /usr/local "$T" && \
    apt-get purge -y --auto-remove $buildDeps

# Static linking for C++ code
RUN ln -s /usr/bin/g++ /usr/bin/musl-g++

# Pre-built static libraries from parallel builder stages.
# libpq-builder already contains OpenSSL, so we copy that whole tree first
# then copy only zlib artifacts on top.
COPY --from=libpq-builder /usr/local/musl /usr/local/musl
COPY --from=zlib-builder /usr/local/musl/lib/libz.a /usr/local/musl/lib/libz.a
COPY --from=zlib-builder /usr/local/musl/include/zlib.h /usr/local/musl/include/zlib.h
COPY --from=zlib-builder /usr/local/musl/include/zconf.h /usr/local/musl/include/zconf.h
COPY --from=zlib-builder /usr/local/musl/lib/pkgconfig/zlib.pc /usr/local/musl/lib/pkgconfig/zlib.pc

# git credentials helper
COPY git-credential-ghtoken /usr/local/bin/ghtoken
RUN git config --global credential.https://github.com.helper ghtoken

# Rust toolchain
ENV RUSTUP_HOME=/opt/rust/rustup \
    PATH=/home/rust/.cargo/bin:/opt/rust/cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CARGO_HOME=/opt/rust/cargo

ARG TOOLCHAIN=stable
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain $TOOLCHAIN --profile minimal --no-modify-path && \
    rustup component add rustfmt && \
    rustup component add clippy && \
    rustup target add x86_64-unknown-linux-musl && \
    rustup component add llvm-tools-preview
COPY cargo-config.toml /opt/rust/cargo/config.toml

ENV X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PKG_CONFIG_ALLOW_CROSS=true \
    PKG_CONFIG_ALL_STATIC=true \
    LIBZ_SYS_STATIC=1 \
    TARGET=musl

RUN --mount=type=cache,target=/opt/rust/cargo/registry,sharing=locked \
    --mount=type=cache,target=/opt/rust/cargo/git,sharing=locked \
    cargo install -f cargo-audit && \
    cargo install -f cargo-deb && \
    cargo install -f cargo-llvm-cov

COPY --chmod=440 sudoers /etc/sudoers.d/nopasswd

USER rust
RUN mkdir -p /home/rust/libs /home/rust/src /home/rust/.cargo && \
    ln -s /opt/rust/cargo/config.toml /home/rust/.cargo/config.toml && \
    git config --global credential.https://github.com.helper ghtoken

WORKDIR /home/rust/src
