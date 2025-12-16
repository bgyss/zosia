#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KERNEL_IMAGE="${KERNEL_IMAGE:-$ROOT_DIR/artifacts/aarch64/Image}"
INITRD_IMAGE="${INITRD_IMAGE:-$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz}"
MODEL_DISK_IMAGE="${MODEL_DISK_IMAGE:-$ROOT_DIR/artifacts/model-disk/model.ext4.img}"

RAM_MB="${RAM_MB:-32768}"
SMP="${SMP:-}"
SMP_USER_SET=0
if [[ -n "$SMP" ]]; then
  SMP_USER_SET=1
else
  SMP=4
fi
APPEND_EXTRA="${APPEND_EXTRA:-}"
QEMU_ACCEL="${QEMU_ACCEL:-}"
QEMU_CPU="${QEMU_CPU:-}"
QEMU_SERIAL="${QEMU_SERIAL:-stdio}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need qemu-system-aarch64

if [[ -z "$QEMU_ACCEL" && "$(uname -s)" == "Darwin" ]]; then
  QEMU_ACCEL="hvf"
fi
if [[ -z "$QEMU_CPU" ]]; then
  if [[ -n "$QEMU_ACCEL" && "$QEMU_ACCEL" != "tcg" ]]; then
    QEMU_CPU="host"
  else
    QEMU_CPU="max"
  fi
fi

if [[ "$SMP_USER_SET" -eq 0 && "$RAM_MB" -ge 32768 ]]; then
  SMP=6
fi

if [[ "$RAM_MB" -ge 32768 ]]; then
  if [[ "$APPEND_EXTRA" != *"zosia.llama_threads="* && "$APPEND_EXTRA" != *"zosia.llama_batch_threads="* && "$APPEND_EXTRA" != *"zosia.llama_args="* ]]; then
    APPEND_EXTRA="${APPEND_EXTRA} zosia.llama_threads=6 zosia.llama_batch_threads=6 zosia.llama_args=-b,256,-c,1024"
  fi
fi

if [[ ! -f "$KERNEL_IMAGE" ]]; then
  echo "missing kernel image: $KERNEL_IMAGE" >&2
  echo "run: ./scripts/build-buildroot.sh" >&2
  exit 1
fi

if [[ ! -f "$INITRD_IMAGE" ]]; then
  echo "missing initramfs: $INITRD_IMAGE" >&2
  echo "run: ./scripts/build-buildroot.sh" >&2
  exit 1
fi

UEFI_FD=""
for candidate in \
  "$ROOT_DIR/assets/uefi/edk2-aarch64-code.fd" \
  "/opt/homebrew/share/qemu/edk2-aarch64-code.fd" \
  "/usr/local/share/qemu/edk2-aarch64-code.fd"
do
  if [[ -f "$candidate" ]]; then
    UEFI_FD="$candidate"
    break
  fi
done

qemu_args=(
  -machine virt
  -cpu "${QEMU_CPU}"
  -m "${RAM_MB}"
  -smp "${SMP}"
  -display none
  -serial "${QEMU_SERIAL}"
  -monitor none
  -kernel "$KERNEL_IMAGE"
  -initrd "$INITRD_IMAGE"
  -append "console=ttyAMA0 rdinit=/init panic=-1 ${APPEND_EXTRA}"
)

if [[ -n "$QEMU_ACCEL" ]]; then
  qemu_args+=(-accel "$QEMU_ACCEL")
fi

if [[ -n "$UEFI_FD" && "${ZOSIA_USE_UEFI:-0}" == "1" ]]; then
  qemu_args+=(-bios "$UEFI_FD")
fi

if [[ -f "$MODEL_DISK_IMAGE" ]]; then
  qemu_args+=(
    -drive "if=none,file=${MODEL_DISK_IMAGE},format=raw,id=model,readonly=on"
    -device virtio-blk-device,drive=model
  )
else
  echo "note: model disk not found at $MODEL_DISK_IMAGE (stub prompt will run)" >&2
fi

exec qemu-system-aarch64 "${qemu_args[@]}"
