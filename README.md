# `rust-musl-builder`: Docker container for easily building static Rust binaries

- [Source on GitHub](https://github.com/pyar6329/rust-musl-builder)
- [Changelog](https://github.com/pyar6329/rust-musl-builder/blob/main/CHANGELOG.md)

## What is this?

This image allows you to build static Rust binaries using `diesel`, `sqlx` or `openssl`. These images can be distributed as single executable files with no dependencies, and they should work on any modern Linux system.

The image is published as a multi-arch manifest for `linux/amd64` and `linux/arm64`, so `docker pull` / `docker run` automatically selects the matching architecture on both Intel/AMD and Apple Silicon / AWS Graviton hosts.

To try it, run:

```sh
alias rust-musl-builder='docker run --rm -it -v "$(pwd)":/home/rust/src ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder:latest-llvm-cov'
rust-musl-builder cargo build --release
```

This command assumes that `$(pwd)` is readable and writable by uid 1000, gid 1000. At the moment, it doesn't attempt to cache libraries between builds, so this is best reserved for making final release builds.

For a more realistic example, see the `Dockerfile`s for [examples/using-diesel](./examples/using-diesel) and [examples/using-sqlx](./examples/using-sqlx).

## Deploying your Rust application

With a bit of luck, you should be able to just copy your application binary from `target/x86_64-unknown-linux-musl/release` (or `target/aarch64-unknown-linux-musl/release` on arm64 hosts), and install it directly on any reasonably modern Linux machine of the matching architecture. You can also copy your Rust application into an [Alpine Linux container][]. See below for details!

## Available tags

Images are published to GitHub Container Registry at `ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder`. Tags are named `X.Y.Z-llvm-cov` where `X.Y.Z` matches the Rust toolchain version pinned in [`rust-toolchain`](./rust-toolchain). Each tag is a multi-arch manifest covering both `linux/amd64` and `linux/arm64`.

Each image should be able to compile [examples/using-diesel](./examples/using-diesel) and [examples/using-sqlx](./examples/using-sqlx) on both supported architectures.

## Caching builds

You may be able to speed up build performance by adding the following `-v` commands to the `rust-musl-builder` alias:

```txt
-v cargo-git:/home/rust/.cargo/git
-v cargo-registry:/home/rust/.cargo/registry
-v target:/home/rust/src/target
```

You will also need to fix the permissions on the mounted volumes:

```sh
rust-musl-builder sudo chown -R rust:rust \
  /home/rust/.cargo/git /home/rust/.cargo/registry /home/rust/src/target
```

## How it works

`rust-musl-builder` uses [musl-libc][], [musl-gcc][], and the new [rustup][] `target` support.  It includes static versions of several libraries:

- The standard `musl-libc` libraries.
- OpenSSL, which is needed by many Rust applications.
- `libpq`, which is needed for applications that use `diesel` with PostgreSQL.
- `libz`, which is needed by `libpq`.
- SQLite3. See [examples/using-diesel](./examples/using-diesel/).

This library also sets up the environment variables needed to compile popular Rust crates using these libraries.

## Extras

This image also supports the following extra goodies:

- Native `aarch64-unknown-linux-musl` / `x86_64-unknown-linux-musl` toolchains, picked automatically from the pulled image's architecture.
- [`cargo about`][about] to collect licenses for your dependencies.
- [`cargo deb`][deb] to build Debian packages.
- [`cargo deny`][deny] to check your Rust project for known security issues.
- [`cargo audit`][audit] to audit `Cargo.lock` for crates with security advisories.
- [`cargo llvm-cov`][llvm-cov] for source-based code coverage.
- [`protoc`][protoc] for compiling Protocol Buffers.

## Making OpenSSL work

If your application uses OpenSSL, you will also need to take a few extra steps to make sure that it can find OpenSSL's list of trusted certificates, which is stored in different locations on different Linux distributions. You can do this using [`openssl-probe`](https://crates.io/crates/openssl-probe) as follows:

```rust
fn main() {
    openssl_probe::init_ssl_cert_env_vars();
    //... your code
}
```

## Making Diesel work

In addition to setting up OpenSSL, you'll need to add the following lines to your `Cargo.toml`:

```toml
[dependencies]
diesel = { version = "1", features = ["postgres", "sqlite"] }

# Needed for sqlite.
libsqlite3-sys = { version = "*", features = ["bundled"] }

# Needed for Postgres.
openssl = "*"
```

For PostgreSQL, you'll also need to include `diesel` and `openssl` in your `main.rs` in the following order (in order to avoid linker errors):

```toml
extern crate openssl;
#[macro_use]
extern crate diesel;
```

If this doesn't work, you _might_ be able to fix it by reversing the order.

## Making tiny Docker images with Alpine Linux and Rust binaries

Docker now supports [multistage builds][multistage], which make it easy to build your Rust application with `rust-musl-builder` and deploy it using [Alpine Linux][]. For a working example, see [`examples/using-diesel/Dockerfile`](./examples/using-diesel/Dockerfile).

[multistage]: https://docs.docker.com/engine/userguide/eng-image/multistage-build/
[Alpine Linux]: https://alpinelinux.org/

## Adding more C libraries

If you're using Docker crates which require specific C libraries to be installed, you can create a `Dockerfile` based on this one, and use `musl-gcc` to compile the libraries you need.  For an example, see [`examples/adding-a-library/Dockerfile`](./examples/adding-a-library/Dockerfile). This usually involves a bit of experimentation for each new library, but it seems to work well for most simple, standalone libraries.

If you need an especially common library, please feel free to submit a pull request adding it to the main `Dockerfile`!  We'd like to support popular Rust crates out of the box.

## ARM support

ARM (`aarch64` / `arm64`) is a first-class target of this container image. The published image is a multi-arch manifest, so on Apple Silicon or AWS Graviton hosts `docker pull` / `docker run` transparently selects the `linux/arm64` variant, and the default build target becomes `aarch64-unknown-linux-musl`. On `x86_64` hosts the `linux/amd64` variant is selected and the default target is `x86_64-unknown-linux-musl`.

Both variants ship statically built OpenSSL, libpq, and zlib against `musl-libc`, so the same `cargo build --release` works on each architecture without additional flags. Binaries are written to `target/<target-triple>/release`.

If you want to force a specific platform (for example, to build arm64 binaries from an amd64 host with QEMU), pass `--platform` to Docker:

```sh
docker run --rm -it --platform=linux/arm64 \
  -v "$(pwd)":/home/rust/src \
  ghcr.io/pyar6329/rust-musl-builder/rust-musl-builder:latest-llvm-cov \
  cargo build --release
```

## Development notes

After modifying the image, run `./test-image` to make sure that everything works.

## Other ways to build portable Rust binaries

If for some reason this image doesn't meet your needs, there's a variety of other people working on similar projects:

- [messense/rust-musl-cross](https://github.com/messense/rust-musl-cross) shows how to build binaries for many different architectures.
- [japaric/rust-cross](https://github.com/japaric/rust-cross) has extensive instructions on how to cross-compile Rust applications.
- [clux/muslrust](https://github.com/clux/muslrust) also supports libcurl.
- [golddranks/rust_musl_docker](https://github.com/golddranks/rust_musl_docker). Another Docker image.

## License

Either the [Apache 2.0 license](./LICENSE-APACHE.txt), or the
[MIT license](./LICENSE-MIT.txt).

[Alpine Linux container]: https://hub.docker.com/_/alpine/
[about]: https://github.com/EmbarkStudios/cargo-about
[deb]: https://github.com/mmstick/cargo-deb
[deny]: https://github.com/EmbarkStudios/cargo-deny
[audit]: https://github.com/rustsec/rustsec/tree/main/cargo-audit
[llvm-cov]: https://github.com/taiki-e/cargo-llvm-cov
[protoc]: https://github.com/protocolbuffers/protobuf
[musl-libc]: http://www.musl-libc.org/
[musl-gcc]: http://www.musl-libc.org/how.html
[rustup]: https://www.rustup.rs/
