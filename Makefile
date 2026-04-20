SHELL := /usr/bin/env bash

RUST_VERSION := $(shell tr -d '[:space:]' < rust-toolchain)
IMAGE_BASE := rust-musl-builder
TAG := $(IMAGE_BASE):$(RUST_VERSION)-llvm-cov

.PHONY: help build clean-cache clean-mount-cache clean-all version

help:
	@echo "Targets:"
	@echo "  make build             Build image ($(TAG))"
	@echo "  make clean-cache       Remove local buildx cache (.tmp/buildx-cache)"
	@echo "  make clean-mount-cache Remove BuildKit cache-mount contents (apt / downloads / cargo registry)"
	@echo "  make clean-all         Clean both caches"
	@echo "  make version           Print the Rust toolchain version"

build:
	./build-local.sh

clean-cache:
	rm -rf .tmp/buildx-cache

clean-mount-cache:
	docker buildx prune --filter 'type=exec.cachemount' -f

clean-all: clean-cache clean-mount-cache

version:
	@echo $(RUST_VERSION)
