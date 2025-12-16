#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
usage: ./scripts/make-model-disk.sh /path/to/model.gguf [--out path] [--extra-mib N] [--use-docker]

Creates a raw ext4 image containing /model.gguf at filesystem root.
The image is intended to be attached to QEMU as a virtio-blk disk and mounted at /models.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

MODEL_PATH="$1"
shift

OUT_PATH="${OUT_PATH:-$ROOT_DIR/artifacts/model-disk/model.ext4.img}"
EXTRA_MIB="${EXTRA_MIB:-512}"
USE_DOCKER="${USE_DOCKER:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_PATH="$2"; shift 2 ;;
    --extra-mib) EXTRA_MIB="$2"; shift 2 ;;
    --use-docker) USE_DOCKER="1"; shift ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "model not found: $MODEL_PATH" >&2
  exit 1
fi

file_size_bytes() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

MODEL_BYTES="$(file_size_bytes "$MODEL_PATH")"
TOTAL_MIB="$(( (MODEL_BYTES + 1024*1024 - 1) / (1024*1024) + EXTRA_MIB ))"

mkdir -p "$(dirname "$OUT_PATH")"

if [[ "$(uname -s)" == "Darwin" && "${ZOSIA_IN_DOCKER:-0}" != "1" && "$USE_DOCKER" != "1" ]]; then
  if [[ "$MODEL_BYTES" -ge $((2 * 1024 * 1024 * 1024)) ]]; then
    echo "model is larger than 2GiB; macOS debugfs often fails with 'Ext2 file too big'." >&2
    echo "rerun with: ./scripts/make-model-disk.sh \"$MODEL_PATH\" --out \"$OUT_PATH\" --extra-mib \"$EXTRA_MIB\" --use-docker" >&2
    exit 1
  fi
fi

abs_path() {
  local target="$1"
  if [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
  else
    (cd "$(dirname "$target")" && printf "%s/%s\n" "$(pwd -P)" "$(basename "$target")")
  fi
}

run_in_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found; install Docker Desktop or rerun on Linux" >&2
    exit 1
  fi

  local model_abs out_abs model_rel out_rel
  model_abs="$(abs_path "$MODEL_PATH")"
  out_abs="$(abs_path "$OUT_PATH")"

  case "$model_abs" in
    "$ROOT_DIR"/*) model_rel="${model_abs#$ROOT_DIR/}" ;;
    *) echo "model path must be under $ROOT_DIR for --use-docker" >&2; exit 1 ;;
  esac

  case "$out_abs" in
    "$ROOT_DIR"/*) out_rel="${out_abs#$ROOT_DIR/}" ;;
    *) echo "output path must be under $ROOT_DIR for --use-docker" >&2; exit 1 ;;
  esac

  docker run --rm \
    -e ZOSIA_IN_DOCKER=1 \
    -v "$ROOT_DIR":/work \
    -w /work \
    debian:bookworm-slim \
    bash -lc "apt-get update >/dev/null && apt-get install -y e2fsprogs >/dev/null && ./scripts/make-model-disk.sh \"$model_rel\" --out \"$out_rel\" --extra-mib \"$EXTRA_MIB\""
  exit $?
}

if [[ "${ZOSIA_IN_DOCKER:-0}" != "1" && "$USE_DOCKER" == "1" ]]; then
  run_in_docker
fi

need mkfs.ext4
need debugfs

echo "creating ext4 image: $OUT_PATH (${TOTAL_MIB} MiB)"
rm -f "$OUT_PATH"
truncate -s "${TOTAL_MIB}M" "$OUT_PATH"
mkfs.ext4 -L ZOSIA_MODEL -m 0 -F "$OUT_PATH" >/dev/null

echo "writing model into filesystem as /model.gguf (this may take a while)..."
tmp_err="$(mktemp)"
if ! debugfs -w -R "write \"$MODEL_PATH\" model.gguf" "$OUT_PATH" >"$tmp_err" 2>&1; then
  echo "failed to write model into image" >&2
  cat "$tmp_err" >&2 || true
  rm -f "$tmp_err"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macOS e2fsprogs can error on >2GiB files; try: ./scripts/make-model-disk.sh \"$MODEL_PATH\" --out \"$OUT_PATH\" --extra-mib \"$EXTRA_MIB\" --use-docker" >&2
  fi
  exit 1
fi
if grep -q "Ext2 file too big" "$tmp_err"; then
  echo "failed to write model into image (Ext2 file too big)" >&2
  rm -f "$tmp_err"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macOS e2fsprogs can error on >2GiB files; try: ./scripts/make-model-disk.sh \"$MODEL_PATH\" --out \"$OUT_PATH\" --extra-mib \"$EXTRA_MIB\" --use-docker" >&2
  fi
  exit 1
fi
rm -f "$tmp_err"

echo "wrote: $OUT_PATH"
