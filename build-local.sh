#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

host_platform() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "linux/amd64" ;;
    arm64|aarch64)  echo "linux/arm64" ;;
    *)              echo "linux/$(uname -m)" ;;
  esac
}

RUST_VERSION="$(tr -d '[:space:]' < rust-toolchain)"
IMAGE_BASE="rust-musl-builder"
CACHE_DIR="${SCRIPT_DIR}/.tmp/buildx-cache"
PLATFORM="${PLATFORM:-$(host_platform)}"
TAG="${IMAGE_BASE}:${RUST_VERSION}-llvm-cov"

mkdir -p "$CACHE_DIR"

echo ">>> Building ${TAG} (platform=${PLATFORM})"
echo ">>> Cache dir: ${CACHE_DIR}"

docker buildx build \
  --progress=plain \
  --load \
  --platform "$PLATFORM" \
  --file ./Dockerfile \
  --tag "$TAG" \
  --build-arg "TOOLCHAIN=${RUST_VERSION}" \
  --cache-from "type=local,src=${CACHE_DIR}" \
  --cache-to "type=local,dest=${CACHE_DIR},mode=max" \
  .

echo ">>> Built ${TAG}"
