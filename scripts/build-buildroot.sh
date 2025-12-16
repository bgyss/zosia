#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=versions.sh
source "$ROOT_DIR/scripts/versions.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
usage: ./scripts/build-buildroot.sh

Builds the aarch64 kernel + initramfs via Buildroot.

On macOS, this script prefers running Buildroot inside Docker (set ZOSIA_NO_DOCKER=1 to disable).
EOF
  exit 0
fi

BUILDROOT_SRC_DIR="${BUILDROOT_SRC_DIR:-$ROOT_DIR/buildroot/buildroot-src}"
BUILDROOT_OUT_DIR="${BUILDROOT_OUT_DIR:-$ROOT_DIR/buildroot/output}"
BUILDROOT_EXTERNAL_DIR="${BUILDROOT_EXTERNAL_DIR:-$ROOT_DIR/buildroot/external}"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/artifacts/aarch64}"

MAKEFLAGS_EXTRA=()
if [[ "${ZOSIA_MAKE_SILENT:-0}" == "1" ]]; then
  MAKEFLAGS_EXTRA+=(-s)
fi

if [[ "${ZOSIA_IN_DOCKER:-0}" != "1" && "$(uname -s)" == "Darwin" && "${ZOSIA_NO_DOCKER:-0}" != "1" ]]; then
  if command -v docker >/dev/null 2>&1; then
    if ! docker info >/dev/null 2>&1; then
      echo "Docker is installed but the daemon is not reachable." >&2
      echo "Start Docker Desktop (or your Docker VM, e.g. Colima) and re-run." >&2
      exit 1
    fi
    echo "macOS detected; building via Docker..."

    # Avoid bind-mounting the workspace on macOS by default (VirtioFS has been observed to
    # trigger Docker Desktop instability under heavy Buildroot workloads). Instead, stream
    # just the needed source directories into the container and persist Buildroot state in
    # Docker volumes.
    if [[ "${ZOSIA_DOCKER_MOUNT_WORKSPACE:-0}" == "1" ]]; then
      exec docker run --rm \
        -v "$ROOT_DIR:/work" \
        -w /work \
        -e ZOSIA_IN_DOCKER=1 \
        -e ZOSIA_JOBS="${ZOSIA_JOBS:-2}" \
        -e FORCE_UNSAFE_CONFIGURE=1 \
        -e ZOSIA_BUILDROOT_REF \
        -e BUILDROOT_SRC_DIR \
        -e BUILDROOT_OUT_DIR \
        -e BUILDROOT_EXTERNAL_DIR \
        -e ARTIFACTS_DIR \
        debian:bookworm \
        bash -lc 'apt-get update && apt-get install -y bc bison build-essential cpio file flex git libncurses5-dev libssl-dev python3 rsync unzip wget && ./scripts/build-buildroot.sh'
    fi

    CONTAINER_NAME="zosia-buildroot-$$-$(date +%s)"
    SRC_VOL="${ZOSIA_BUILDROOT_SRC_VOL:-zosia-buildroot-src}"
    OUT_VOL="${ZOSIA_BUILDROOT_OUT_VOL:-zosia-buildroot-out}"

    docker volume create "$SRC_VOL" >/dev/null
    docker volume create "$OUT_VOL" >/dev/null

    cleanup_container() {
      docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup_container EXIT

    docker create --name "$CONTAINER_NAME" -i \
      -v "${SRC_VOL}:/br-src" \
      -v "${OUT_VOL}:/br-out" \
      -e ZOSIA_IN_DOCKER=1 \
      -e ZOSIA_JOBS="${ZOSIA_JOBS:-2}" \
      -e ZOSIA_MAKE_SILENT=1 \
      -e FORCE_UNSAFE_CONFIGURE=1 \
      -e ZOSIA_BUILDROOT_REF \
      -e BUILDROOT_SRC_DIR="/br-src" \
      -e BUILDROOT_OUT_DIR="/br-out" \
      -e BUILDROOT_EXTERNAL_DIR="/work/buildroot/external" \
      -e ARTIFACTS_DIR="/work/artifacts/aarch64" \
      debian:bookworm \
      bash -lc 'apt-get update && apt-get install -y bc bison build-essential cpio file flex git libncurses5-dev libssl-dev python3 rsync unzip wget >/dev/null && mkdir -p /work && tar -x -C /work && cd /work && ./scripts/build-buildroot.sh' \
      >/dev/null

    (cd "$ROOT_DIR" && tar -cf - scripts buildroot/external initramfs) | docker start -a -i "$CONTAINER_NAME"

    mkdir -p "$ARTIFACTS_DIR"
    docker cp "$CONTAINER_NAME:/work/artifacts/aarch64/Image" "$ARTIFACTS_DIR/Image"
    docker cp "$CONTAINER_NAME:/work/artifacts/aarch64/initramfs.cpio.gz" "$ARTIFACTS_DIR/initramfs.cpio.gz"

    echo "wrote:"
    echo "  $ARTIFACTS_DIR/Image"
    echo "  $ARTIFACTS_DIR/initramfs.cpio.gz"
    exit 0
  fi
  echo "macOS detected but Docker not found; Buildroot typically requires Linux." >&2
  echo "Install Docker Desktop or set ZOSIA_NO_DOCKER=1 to try native." >&2
  exit 1
fi

jobs() {
  if [[ -n "${ZOSIA_JOBS:-}" ]]; then
    echo "$ZOSIA_JOBS"
    return
  fi
  if command -v nproc >/dev/null 2>&1; then nproc; return; fi
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

need git
need make

if [[ ! -d "$BUILDROOT_EXTERNAL_DIR" ]]; then
  echo "missing Buildroot external tree at $BUILDROOT_EXTERNAL_DIR" >&2
  echo "expected files under buildroot/external/ (configs/board/)" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/buildroot" "$BUILDROOT_OUT_DIR" "$ARTIFACTS_DIR"

if [[ ! -d "$BUILDROOT_SRC_DIR/.git" ]]; then
  echo "cloning Buildroot @ ${ZOSIA_BUILDROOT_REF} -> $BUILDROOT_SRC_DIR"
  git clone --filter=blob:none https://github.com/buildroot/buildroot.git "$BUILDROOT_SRC_DIR"
fi

echo "checking out Buildroot @ ${ZOSIA_BUILDROOT_REF}"
git -C "$BUILDROOT_SRC_DIR" fetch --tags --force
git -C "$BUILDROOT_SRC_DIR" checkout -f "$ZOSIA_BUILDROOT_REF"

echo "configuring..."
make "${MAKEFLAGS_EXTRA[@]}" -C "$BUILDROOT_SRC_DIR" \
  O="$BUILDROOT_OUT_DIR" \
  BR2_EXTERNAL="$BUILDROOT_EXTERNAL_DIR" \
  zosia_aarch64_defconfig

echo "building (this can take a while)..."
make "${MAKEFLAGS_EXTRA[@]}" -C "$BUILDROOT_SRC_DIR" \
  O="$BUILDROOT_OUT_DIR" \
  BR2_EXTERNAL="$BUILDROOT_EXTERNAL_DIR" \
  -j"$(jobs)"

KERNEL_IMAGE="$BUILDROOT_OUT_DIR/images/Image"
INITRAMFS_CPIO_GZ="$BUILDROOT_OUT_DIR/images/rootfs.cpio.gz"

if [[ ! -f "$KERNEL_IMAGE" ]]; then
  echo "expected kernel at $KERNEL_IMAGE" >&2
  exit 1
fi
if [[ ! -f "$INITRAMFS_CPIO_GZ" ]]; then
  echo "expected initramfs at $INITRAMFS_CPIO_GZ" >&2
  exit 1
fi

cp -f "$KERNEL_IMAGE" "$ARTIFACTS_DIR/Image"
cp -f "$INITRAMFS_CPIO_GZ" "$ARTIFACTS_DIR/initramfs.cpio.gz"

echo "wrote:"
echo "  $ARTIFACTS_DIR/Image"
echo "  $ARTIFACTS_DIR/initramfs.cpio.gz"
