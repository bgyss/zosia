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

# Validate artifact sizes
validate_artifacts() {
  local kernel_size initrd_size

  # Get file sizes (works on both Linux and macOS)
  kernel_size=$(stat -c%s "$KERNEL_IMAGE" 2>/dev/null || stat -f%z "$KERNEL_IMAGE" 2>/dev/null || echo 0)
  initrd_size=$(stat -c%s "$INITRD_IMAGE" 2>/dev/null || stat -f%z "$INITRD_IMAGE" 2>/dev/null || echo 0)

  # Kernel should be at least 10MB (typical aarch64 kernel is 15-30MB)
  if [[ "$kernel_size" -lt 10000000 ]]; then
    echo "ERROR: kernel image too small ($kernel_size bytes, expected >10MB)" >&2
    echo "       This may indicate a corrupted or incomplete build" >&2
    exit 1
  fi

  # Initramfs should be at least 1MB
  if [[ "$initrd_size" -lt 1000000 ]]; then
    echo "ERROR: initramfs too small ($initrd_size bytes, expected >1MB)" >&2
    echo "       This may indicate a corrupted or incomplete build" >&2
    exit 1
  fi

  # Validate initramfs is valid gzip
  if ! gzip -t "$INITRD_IMAGE" 2>/dev/null; then
    echo "ERROR: initramfs is not a valid gzip file" >&2
    exit 1
  fi

  echo "artifacts validated: kernel=$(numfmt --to=iec $kernel_size 2>/dev/null || echo "${kernel_size}B"), initrd=$(numfmt --to=iec $initrd_size 2>/dev/null || echo "${initrd_size}B")"
}

validate_artifacts

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
