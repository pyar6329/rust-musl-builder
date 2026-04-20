# `rust-musl-builder`

Docker image for building static Rust binaries against `musl-libc`. Includes OpenSSL, `libpq`, `libz`, SQLite3 pre-built statically, so crates like `diesel`, `sqlx`, and `openssl` work out of the box.

Images are published as a multi-arch manifest (`linux/amd64` + `linux/arm64`) to `ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder`. Tags are `X.Y.Z-llvm-cov` matching the Rust version in [`rust-toolchain`](./rust-toolchain). See the [GitHub Container Registry package page](https://github.com/pyar6329/rust-musl-builder/pkgs/container/rust-musl-builder%2Frust-musl-builder) for the full tag list.

## Usage

```sh
docker pull ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder:1.95.0-llvm-cov

docker run --rm -it \
  -v "$(pwd)":/home/rust/src \
  ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder:1.95.0-llvm-cov \
  cargo build --release
```

Binaries are written to `target/<target-triple>/release/`. The target defaults to the host architecture (`x86_64-unknown-linux-musl` on amd64, `aarch64-unknown-linux-musl` on arm64). To force the other platform, pass `--platform=linux/arm64` (or `linux/amd64`) to `docker run`.

`$(pwd)` must be readable/writable by uid/gid `1000`.

## Included tools

- Rust toolchain + `rustfmt`, `clippy`, `llvm-tools-preview`
- [`cargo-about`](https://github.com/EmbarkStudios/cargo-about), [`cargo-audit`](https://github.com/rustsec/rustsec/tree/main/cargo-audit), [`cargo-deb`](https://github.com/mmstick/cargo-deb), [`cargo-deny`](https://github.com/EmbarkStudios/cargo-deny), [`cargo-llvm-cov`](https://github.com/taiki-e/cargo-llvm-cov)
- [`protoc`](https://github.com/protocolbuffers/protobuf)

## OpenSSL certificates

If your binary uses OpenSSL, load the host's CA bundle at startup with [`openssl-probe`](https://crates.io/crates/openssl-probe):

```rust
fn main() {
    openssl_probe::init_ssl_cert_env_vars();
    // ...
}
```

## License

[Apache 2.0](./LICENSE-APACHE.txt) or [MIT](./LICENSE-MIT.txt).
