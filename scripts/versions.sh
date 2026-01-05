#!/usr/bin/env bash
set -euo pipefail

# zosia project version
export ZOSIA_VERSION="${ZOSIA_VERSION:-0.0.2-alpha}"

# Pinned refs for reproducible builds. Override via env vars if you need to.
export ZOSIA_BUILDROOT_REF="${ZOSIA_BUILDROOT_REF:-2024.11.1}"

export ZOSIA_LLAMA_CPP_REF="${ZOSIA_LLAMA_CPP_REF:-2995341730f18deb64faa4538bda113328fd791f}"
