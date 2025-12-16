#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

KERNEL_IMAGE="${KERNEL_IMAGE:-$ROOT_DIR/artifacts/aarch64/Image}"
INITRD_IMAGE="${INITRD_IMAGE:-$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need qemu-system-aarch64

if [[ ! -f "$KERNEL_IMAGE" || ! -f "$INITRD_IMAGE" ]]; then
  echo "missing artifacts; run ./scripts/build-buildroot.sh first" >&2
  exit 1
fi

tmp_out="$(mktemp)"
trap 'rm -f "$tmp_out"' EXIT

cmd=(
  qemu-system-aarch64
  -machine virt
  -cpu max
  -m 1024
  -smp 2
  -display none
  -serial stdio
  -monitor none
  -kernel "$KERNEL_IMAGE"
  -initrd "$INITRD_IMAGE"
  -append "console=ttyAMA0 rdinit=/init zosia.ci=1 panic=-1"
)

echo "booting smoke VM..."
if command -v timeout >/dev/null 2>&1; then
  timeout 30 "${cmd[@]}" | tee "$tmp_out" || true
else
  "${cmd[@]}" | tee "$tmp_out" || true
fi

rg -q "zosia: init" "$tmp_out"
echo "smoke boot OK"
