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
ARG TARGETARCH
RUN --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    case "$TARGETARCH" in \
      amd64) ARCH_GNU="x86_64-linux-gnu"; OSSL_TARGET="linux-x86_64"; EXTRA_CFLAGS="" ;; \
      arm64) ARCH_GNU="aarch64-linux-gnu"; OSSL_TARGET="linux-aarch64"; EXTRA_CFLAGS="-mno-outline-atomics" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    mkdir -p /usr/local/musl/include && \
    ln -s /usr/include/linux /usr/local/musl/include/linux && \
    ln -s "/usr/include/${ARCH_GNU}/asm" /usr/local/musl/include/asm && \
    ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic && \
    T="/downloads/openssl-${OPENSSL_VERSION}.tar.gz" && \
    tar tzf "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" && mv "$T.part" "$T"; } && \
    cd /tmp && tar xzf "$T" && cd "openssl-${OPENSSL_VERSION}" && \
    env CC=musl-gcc ./Configure no-shared no-zlib no-tests no-quic no-fuzz-libfuzzer no-fuzz-afl -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY $EXTRA_CFLAGS "$OSSL_TARGET" && \
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
    tar tzf "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" && mv "$T.part" "$T"; } && \
    cd /tmp && tar xzf "$T" && cd "zlib-${ZLIB_VERSION}" && \
    CC=musl-gcc ./configure --static --prefix=/usr/local/musl && \
    make -j"$(nproc)" && make install

# ==========================================================================
# libpq-builder: static libpq against musl (needs OpenSSL, not zlib)
# ==========================================================================
FROM base AS libpq-builder
ARG POSTGRESQL_VERSION
COPY --from=openssl-builder /usr/local/musl /usr/local/musl
RUN --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    T="/downloads/postgresql-${POSTGRESQL_VERSION}.tar.gz" && \
    tar tzf "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "https://ftp.postgresql.org/pub/source/v${POSTGRESQL_VERSION}/postgresql-${POSTGRESQL_VERSION}.tar.gz" && mv "$T.part" "$T"; } && \
    cd /tmp && tar xzf "$T" && cd "postgresql-${POSTGRESQL_VERSION}" && \
    CC=musl-gcc \
    CPPFLAGS="-I/usr/local/musl/include" \
    LDFLAGS="-L/usr/local/musl/lib -L/usr/local/musl/lib64" \
    ./configure --with-openssl --without-readline --without-icu --without-zstd --without-lz4 --without-zlib --prefix=/usr/local/musl && \
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
ARG TARGETARCH
ARG TOOLCHAIN=stable

# Runtime deps, extra tools, pre-built binary downloads (cargo-about, cargo-deny, protoc)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/downloads,sharing=locked \
    set -eux && \
    case "$TARGETARCH" in \
      amd64) RUST_ARCH="x86_64"; PROTOC_ARCH="x86_64" ;; \
      arm64) RUST_ARCH="aarch64"; PROTOC_ARCH="aarch_64" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
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
    T="/downloads/cargo-about-${CARGO_ABOUT_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz" && \
    tar tzf "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "https://github.com/EmbarkStudios/cargo-about/releases/download/${CARGO_ABOUT_VERSION}/cargo-about-${CARGO_ABOUT_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz" && mv "$T.part" "$T"; } && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-about-${CARGO_ABOUT_VERSION}-${RUST_ARCH}-unknown-linux-musl/cargo-about" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-about-${CARGO_ABOUT_VERSION}-${RUST_ARCH}-unknown-linux-musl" && \
    T="/downloads/cargo-deny-${CARGO_DENY_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz" && \
    tar tzf "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "https://github.com/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/cargo-deny-${CARGO_DENY_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz" && mv "$T.part" "$T"; } && \
    tar -C /tmp -xf "$T" && \
    mv "/tmp/cargo-deny-${CARGO_DENY_VERSION}-${RUST_ARCH}-unknown-linux-musl/cargo-deny" /usr/local/bin/ && \
    rm -rf "/tmp/cargo-deny-${CARGO_DENY_VERSION}-${RUST_ARCH}-unknown-linux-musl" && \
    T="/downloads/protoc-${PROTOBUF_VERSION}-linux-${PROTOC_ARCH}.zip" && \
    unzip -tq "$T" >/dev/null 2>&1 || { rm -f "$T" && curl -fL --retry 3 -o "$T.part" "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-${PROTOC_ARCH}.zip" && mv "$T.part" "$T"; } && \
    unzip -o -d /usr/local "$T" && \
    apt-get purge -y --auto-remove $buildDeps

# Static linking for C++ code
RUN ln -s /usr/bin/g++ /usr/bin/musl-g++

# Pre-built static libraries from parallel builder stages.
# libpq-builder already contains OpenSSL, so copy that whole tree first,
# then copy zlib artifacts on top (libpq is built --without-zlib,
# but Rust projects using libz-sys still need libz.a here).
COPY --from=libpq-builder /usr/local/musl /usr/local/musl
COPY --from=zlib-builder /usr/local/musl/lib/libz.a /usr/local/musl/lib/libz.a
COPY --from=zlib-builder /usr/local/musl/include/zlib.h /usr/local/musl/include/zlib.h
COPY --from=zlib-builder /usr/local/musl/include/zconf.h /usr/local/musl/include/zconf.h
COPY --from=zlib-builder /usr/local/musl/lib/pkgconfig/zlib.pc /usr/local/musl/lib/pkgconfig/zlib.pc

# git credentials helper
COPY git-credential-ghtoken /usr/local/bin/ghtoken
RUN git config --global credential.https://github.com.helper ghtoken

# Rust toolchain + cargo config generated with the correct default target
ENV RUSTUP_HOME=/opt/rust/rustup \
    PATH=/home/rust/.cargo/bin:/opt/rust/cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CARGO_HOME=/opt/rust/cargo

RUN set -eux && \
    case "$TARGETARCH" in \
      amd64) RUST_TARGET="x86_64-unknown-linux-musl" ;; \
      arm64) RUST_TARGET="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    curl https://sh.rustup.rs -sSf | \
      sh -s -- -y --default-toolchain "$TOOLCHAIN" --profile minimal --no-modify-path && \
    rustup component add rustfmt && \
    rustup component add clippy && \
    rustup target add "$RUST_TARGET" && \
    rustup component add llvm-tools-preview && \
    mkdir -p /opt/rust/cargo && \
    printf '[build]\ntarget = "%s"\n\n[target.armv7-unknown-linux-musleabihf]\nlinker = "arm-linux-gnueabihf-gcc"\n\n[net]\ngit-fetch-with-cli = true\n' "$RUST_TARGET" > /opt/rust/cargo/config.toml

# Arch-specific vars are checked first by openssl-sys / pq-sys; declare both
# so the image works the same on amd64 and arm64.
ENV OPENSSL_DIR=/usr/local/musl/ \
    OPENSSL_STATIC=1 \
    X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    X86_64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl/ \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_STATIC=1 \
    PQ_LIB_STATIC_X86_64_UNKNOWN_LINUX_MUSL=1 \
    PQ_LIB_STATIC_AARCH64_UNKNOWN_LINUX_MUSL=1 \
    PG_CONFIG_X86_64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
    PG_CONFIG_AARCH64_UNKNOWN_LINUX_GNU=/usr/bin/pg_config \
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
