#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=versions.sh
source "$ROOT_DIR/scripts/versions.sh"

LLAMA_SRC_DIR="${LLAMA_SRC_DIR:-$ROOT_DIR/third_party/llama.cpp}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need git

mkdir -p "$(dirname "$LLAMA_SRC_DIR")"

if [[ ! -d "$LLAMA_SRC_DIR/.git" ]]; then
  echo "cloning llama.cpp @ ${ZOSIA_LLAMA_CPP_REF} -> $LLAMA_SRC_DIR"
  git clone --filter=blob:none https://github.com/ggerganov/llama.cpp.git "$LLAMA_SRC_DIR"
fi

echo "checking out llama.cpp @ ${ZOSIA_LLAMA_CPP_REF}"
git -C "$LLAMA_SRC_DIR" fetch --tags --force
git -C "$LLAMA_SRC_DIR" checkout -f "$ZOSIA_LLAMA_CPP_REF"

cat <<EOF
llama.cpp is checked out at:
  $LLAMA_SRC_DIR

Note:
  - The guest binary is built via Buildroot (see BR2_PACKAGE_LLAMA_CPP) and installed into the initramfs as /usr/bin/llama-run.
  - This script is only a convenience checkout for local hacking/debugging.
EOF
