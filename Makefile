SHELL := /usr/bin/env bash

RUST_VERSION := $(shell tr -d '[:space:]' < rust-toolchain)
IMAGE_BASE := rust-musl-builder
TAG := $(IMAGE_BASE):$(RUST_VERSION)-llvm-cov

.PHONY: help build clean-cache version

help:
	@echo "Targets:"
	@echo "  make build       Build image ($(TAG))"
	@echo "  make clean-cache Remove local buildx cache (.tmp/buildx-cache)"
	@echo "  make version     Print the Rust toolchain version"

build:
	./build-local.sh

clean-cache:
	rm -rf .tmp/buildx-cache

version:
	@echo $(RUST_VERSION)
