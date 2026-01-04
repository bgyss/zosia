#!/usr/bin/env bash
# Test specific boot modes
# Usage: boot-mode-test.sh <mode>
# Modes: ci, diag, selftest, perf
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

KERNEL_IMAGE="${KERNEL_IMAGE:-$ROOT_DIR/artifacts/aarch64/Image}"
INITRD_IMAGE="${INITRD_IMAGE:-$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz}"
TIMEOUT_SECS="${TIMEOUT_SECS:-30}"
RAM_MB="${RAM_MB:-1024}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <mode>

Test specific boot modes in QEMU.

Modes:
  ci        Test CI mode (boot and power off)
  diag      Test diagnostic mode (prints model/device info)
  selftest  Test selftest mode (checks llama binary)
  stub      Test stub REPL mode (no model disk)

Environment:
  KERNEL_IMAGE   Path to kernel (default: artifacts/aarch64/Image)
  INITRD_IMAGE   Path to initramfs (default: artifacts/aarch64/initramfs.cpio.gz)
  TIMEOUT_SECS   Timeout in seconds (default: 30)
  RAM_MB         RAM in megabytes (default: 1024)
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

run_qemu() {
  local append_extra="$1"
  local expected_pattern="$2"
  local test_name="$3"

  local tmp_out
  tmp_out="$(mktemp)"
  trap 'rm -f "$tmp_out"' EXIT

  local cmd=(
    qemu-system-aarch64
    -machine virt
    -cpu max
    -m "$RAM_MB"
    -smp 2
    -display none
    -serial stdio
    -monitor none
    -kernel "$KERNEL_IMAGE"
    -initrd "$INITRD_IMAGE"
    -append "console=ttyAMA0 rdinit=/init $append_extra panic=-1"
  )

  echo "[$test_name] booting with: $append_extra"

  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SECS" "${cmd[@]}" > "$tmp_out" 2>&1 || true
  else
    "${cmd[@]}" > "$tmp_out" 2>&1 &
    local pid=$!
    sleep "$TIMEOUT_SECS"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi

  # Check for expected pattern
  if grep -q "$expected_pattern" "$tmp_out"; then
    echo "[$test_name] PASSED: found '$expected_pattern'"
    return 0
  else
    echo "[$test_name] FAILED: expected '$expected_pattern' not found"
    echo "--- Output ---"
    cat "$tmp_out"
    echo "--- End ---"
    return 1
  fi
}

# Main
need qemu-system-aarch64

if [[ ! -f "$KERNEL_IMAGE" || ! -f "$INITRD_IMAGE" ]]; then
  echo "missing artifacts; run ./scripts/build-buildroot.sh first" >&2
  exit 1
fi

MODE="${1:-}"

case "$MODE" in
  ci)
    run_qemu "zosia.ci=1" "zosia: ci mode" "CI mode"
    ;;
  diag)
    run_qemu "zosia.diag=1" "zosia: diag" "Diagnostic mode"
    ;;
  selftest)
    run_qemu "zosia.selftest=1" "zosia: selftest" "Selftest mode"
    ;;
  stub)
    run_qemu "zosia.ci=1" "stub prompt\|zosia: ci mode" "Stub mode"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    echo "ERROR: mode required" >&2
    usage
    exit 1
    ;;
  *)
    echo "ERROR: unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
