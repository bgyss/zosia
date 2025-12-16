#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
PERF_TOKENS="${PERF_TOKENS:-}"
PERF_TOKENS_USER_SET=0
if [[ -n "$PERF_TOKENS" ]]; then
  PERF_TOKENS_USER_SET=1
else
  PERF_TOKENS=64
fi
PERF_MIN_TOK_S="${PERF_MIN_TOK_S:-20}"
PERF_TIMEOUT="${PERF_TIMEOUT:-300}"

PERF_THREADS="${PERF_THREADS:-}"
PERF_BATCH_THREADS="${PERF_BATCH_THREADS:-}"
PERF_LLAMA_ARGS="${PERF_LLAMA_ARGS:-}"
PERF_PROFILE="${PERF_PROFILE:-}"
PERF_RUNS="${PERF_RUNS:-1}"
PERF_LOOP="${PERF_LOOP:-0}"
PERF_LOOP_SLEEP="${PERF_LOOP_SLEEP:-2}"
PERF_MATRIX_FILE="${PERF_MATRIX_FILE:-}"
PERF_RESULTS="${PERF_RESULTS:-}"
PERF_FAIL_FAST="${PERF_FAIL_FAST:-1}"
PERF_LOG="${PERF_LOG:-}"
PERF_LOG_DIR="${PERF_LOG_DIR:-}"

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

if [[ ! -f "$MODEL_DISK_IMAGE" ]]; then
  echo "missing model disk; run ./scripts/make-model-disk.sh /path/to/model.gguf" >&2
  exit 1
fi

if [[ -z "$PERF_PROFILE" && -z "$PERF_THREADS" && -z "$PERF_BATCH_THREADS" && -z "$PERF_LLAMA_ARGS" ]]; then
  PERF_PROFILE="phi35_fast"
fi

if [[ "$PERF_PROFILE" == "none" ]]; then
  PERF_PROFILE=""
fi

if [[ -n "$PERF_PROFILE" ]]; then
  case "$PERF_PROFILE" in
    phi35_fast)
      if [[ -z "$PERF_THREADS" ]]; then PERF_THREADS="6"; fi
      if [[ -z "$PERF_BATCH_THREADS" ]]; then PERF_BATCH_THREADS="6"; fi
      if [[ -z "$PERF_LLAMA_ARGS" ]]; then PERF_LLAMA_ARGS="-b,256,-c,1024"; fi
      if [[ "$SMP_USER_SET" -eq 0 ]]; then SMP="6"; fi
      if [[ "$PERF_TOKENS_USER_SET" -eq 0 ]]; then PERF_TOKENS="128"; fi
      ;;
    *)
      echo "unknown PERF_PROFILE: $PERF_PROFILE" >&2
      exit 1
      ;;
  esac
fi

csv_escape() {
  printf '%s' "$1" | sed 's/"/""/g'
}

write_results_header() {
  if [[ -n "$PERF_RESULTS" && ! -s "$PERF_RESULTS" ]]; then
    echo 'timestamp,threads,batch_threads,args,tokens,seconds,tok_per_s,ok' >>"$PERF_RESULTS"
  fi
}

save_logs() {
  local out="$1"
  local err="$2"
  local dest="$3"
  if [[ -z "$dest" ]]; then
    return 0
  fi
  cat "$out" >"$dest"
  if [[ -s "$err" ]]; then
    printf '\n--- stderr ---\n' >>"$dest"
    cat "$err" >>"$dest"
  fi
}

run_once() {
  local threads="$1"
  local batch_threads="$2"
  local llama_args="$3"
  local label="$4"

  local append_extra="zosia.perf=1 zosia.perf.tokens=${PERF_TOKENS}"
  if [[ -n "$threads" ]]; then
    append_extra+=" zosia.llama_threads=${threads}"
  fi
  if [[ -n "$batch_threads" ]]; then
    append_extra+=" zosia.llama_batch_threads=${batch_threads}"
  fi
  if [[ -n "$llama_args" ]]; then
    append_extra+=" zosia.llama_args=${llama_args}"
  fi

  local tmp_out tmp_err log_path
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  log_path=""
  if [[ -n "$PERF_LOG_DIR" ]]; then
    mkdir -p "$PERF_LOG_DIR"
    log_path="${PERF_LOG_DIR}/perf_${label}_$(date +%Y%m%d-%H%M%S).log"
  elif [[ -n "$PERF_LOG" ]]; then
    log_path="$PERF_LOG"
  fi

  echo "booting perf VM (threads=${threads:-auto} batch=${batch_threads:-auto} args=${llama_args:-none})..."
  if command -v timeout >/dev/null 2>&1; then
    QEMU_SERIAL="file:$tmp_out" RAM_MB="$RAM_MB" SMP="$SMP" MODEL_DISK_IMAGE="$MODEL_DISK_IMAGE" APPEND_EXTRA="$append_extra" \
      timeout "$PERF_TIMEOUT" "$ROOT_DIR/scripts/run-qemu-aarch64.sh" 2>"$tmp_err" || true
  else
    QEMU_SERIAL="file:$tmp_out" RAM_MB="$RAM_MB" SMP="$SMP" MODEL_DISK_IMAGE="$MODEL_DISK_IMAGE" APPEND_EXTRA="$append_extra" \
      "$ROOT_DIR/scripts/run-qemu-aarch64.sh" 2>"$tmp_err" || true
  fi

  if ! grep -q "zosia: perf" "$tmp_out"; then
    echo "perf marker not found in VM output" >&2
    if [[ -s "$tmp_err" ]]; then
      echo "stderr:" >&2
      tail -n 200 "$tmp_err" >&2 || true
    fi
    tail -n 200 "$tmp_out" >&2 || true
    save_logs "$tmp_out" "$tmp_err" "$log_path"
    rm -f "$tmp_out" "$tmp_err"
    return 1
  fi

  local tok_line tok_per_s tokens seconds
  tok_line="$(grep -E "zosia: perf tokens=" "$tmp_out" | tail -n 1 || true)"
  if [[ -z "$tok_line" ]]; then
    echo "perf output line not found" >&2
    if [[ -s "$tmp_err" ]]; then
      echo "stderr:" >&2
      tail -n 200 "$tmp_err" >&2 || true
    fi
    tail -n 200 "$tmp_out" >&2 || true
    save_logs "$tmp_out" "$tmp_err" "$log_path"
    rm -f "$tmp_out" "$tmp_err"
    return 1
  fi

  tok_per_s="$(echo "$tok_line" | awk -F 'tok_per_s=' '{print $2}' | awk '{print $1}' | tr -cd '0-9.')"
  tokens="$(echo "$tok_line" | awk -F 'tokens=' '{print $2}' | awk '{print $1}' | tr -cd '0-9')"
  seconds="$(echo "$tok_line" | awk -F 'seconds=' '{print $2}' | awk '{print $1}' | tr -cd '0-9.')"
  if [[ -z "$tok_per_s" && -n "$tokens" && -n "$seconds" ]]; then
    tok_per_s="$(awk -v n="$tokens" -v d="$seconds" 'BEGIN { if (d <= 0) d = 0.0001; printf "%.2f", n / d }')"
  fi
  if [[ -z "$tok_per_s" ]]; then
    echo "perf token rate not found (line: $tok_line)" >&2
    save_logs "$tmp_out" "$tmp_err" "$log_path"
    rm -f "$tmp_out" "$tmp_err"
    return 1
  fi

  local ok=1
  if ! awk -v v="$tok_per_s" -v min="$PERF_MIN_TOK_S" 'BEGIN { exit !(v + 0 >= min + 0) }'; then
    ok=0
  fi

  echo "perf: tok_per_s=${tok_per_s} seconds=${seconds:-?} tokens=${tokens:-?} ok=${ok}"

  if [[ -n "$PERF_RESULTS" ]]; then
    local ts args_escaped
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    args_escaped="$(csv_escape "$llama_args")"
    printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
      "$ts" "${threads:-}" "${batch_threads:-}" "$args_escaped" "${tokens:-}" "${seconds:-}" "${tok_per_s}" "${ok}" \
      >>"$PERF_RESULTS"
  fi

  save_logs "$tmp_out" "$tmp_err" "$log_path"
  rm -f "$tmp_out" "$tmp_err"

  if [[ "$ok" -eq 1 ]]; then
    return 0
  fi
  return 1
}

configs=()
if [[ -n "$PERF_MATRIX_FILE" ]]; then
  if [[ ! -f "$PERF_MATRIX_FILE" ]]; then
    echo "missing PERF_MATRIX_FILE: $PERF_MATRIX_FILE" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -z "$line" ]]; then
      continue
    fi
    configs+=("$line")
  done <"$PERF_MATRIX_FILE"
else
  configs+=("${PERF_THREADS}|${PERF_BATCH_THREADS}|${PERF_LLAMA_ARGS}")
fi

write_results_header

run_all() {
  local idx=0
  for cfg in "${configs[@]}"; do
    idx=$((idx + 1))
    local threads batch args
    IFS='|' read -r threads batch args <<<"$cfg"
    local run
    for ((run = 1; run <= PERF_RUNS; run++)); do
      local label
      label="$(printf "%02d_run%02d" "$idx" "$run")"
      if ! run_once "$threads" "$batch" "$args" "$label"; then
        if [[ "$PERF_FAIL_FAST" == "1" ]]; then
          return 1
        fi
      fi
    done
  done
  return 0
}

if [[ "$PERF_LOOP" == "1" ]]; then
  while :; do
    run_all || true
    sleep "$PERF_LOOP_SLEEP"
  done
else
  run_all
fi
