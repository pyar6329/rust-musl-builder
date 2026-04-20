#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUST_VERSION="$(tr -d '[:space:]' < rust-toolchain)"
IMAGE_BASE="rust-musl-builder"
CACHE_DIR="${SCRIPT_DIR}/.tmp/buildx-cache"
TAG="${IMAGE_BASE}:${RUST_VERSION}-llvm-cov"

mkdir -p "$CACHE_DIR"

echo ">>> Building ${TAG}"
echo ">>> Cache dir: ${CACHE_DIR}"

docker buildx build \
  --load \
  --file ./Dockerfile \
  --tag "$TAG" \
  --build-arg "TOOLCHAIN=${RUST_VERSION}" \
  --cache-from "type=local,src=${CACHE_DIR}" \
  --cache-to "type=local,dest=${CACHE_DIR},mode=max" \
  .

echo ">>> Built ${TAG}"
