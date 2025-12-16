#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
usage: ./scripts/ci/gen-perf-matrix.sh [--out path]

Generates a perf tuning matrix file with lines in the form:
  threads|batch_threads|llama_args

Env overrides:
  OUT_PATH=path
  PERF_MATRIX_THREADS_LIST="4,6,8"
  PERF_MATRIX_BATCH_THREADS_LIST="4,8"   (optional; defaults to threads)
  PERF_MATRIX_ARGS_LIST="-b,256,-c,2048;-b,512,-c,2048"
EOF
}

OUT_PATH="${OUT_PATH:-$ROOT_DIR/perf.matrix}"
PERF_MATRIX_THREADS_LIST="${PERF_MATRIX_THREADS_LIST:-}"
PERF_MATRIX_BATCH_THREADS_LIST="${PERF_MATRIX_BATCH_THREADS_LIST:-}"
PERF_MATRIX_ARGS_LIST="${PERF_MATRIX_ARGS_LIST:-"-b,256,-c,1024;-b,256,-c,2048"}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--out" ]]; then
  OUT_PATH="$2"
fi

detect_cpus() {
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN 2>/dev/null && return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu 2>/dev/null && return
  fi
  echo 4
}

threads_list=()
if [[ -n "$PERF_MATRIX_THREADS_LIST" ]]; then
  IFS=',' read -r -a threads_list <<<"$PERF_MATRIX_THREADS_LIST"
else
  cpu_count="$(detect_cpus)"
  for cand in "$((cpu_count - 2))" "$cpu_count" "$((cpu_count + 2))"; do
    if [[ "$cand" -ge 1 ]]; then
      threads_list+=("$cand")
    fi
  done
fi

if [[ "${#threads_list[@]}" -eq 0 ]]; then
  threads_list=(4)
fi

threads_list_sorted="$(printf '%s\n' "${threads_list[@]}" | sort -n -u | tr '\n' ',')"
threads_list_sorted="${threads_list_sorted%,}"
IFS=',' read -r -a threads_list <<<"$threads_list_sorted"

batch_list=()
if [[ -n "$PERF_MATRIX_BATCH_THREADS_LIST" ]]; then
  IFS=',' read -r -a batch_list <<<"$PERF_MATRIX_BATCH_THREADS_LIST"
fi

IFS=';' read -r -a args_list <<<"$PERF_MATRIX_ARGS_LIST"

mkdir -p "$(dirname "$OUT_PATH")"
{
  echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# format: threads|batch_threads|llama_args"
  for t in "${threads_list[@]}"; do
    if [[ "${#batch_list[@]}" -eq 0 ]]; then
      for args in "${args_list[@]}"; do
        echo "${t}|${t}|${args}"
      done
    else
      for b in "${batch_list[@]}"; do
        for args in "${args_list[@]}"; do
          echo "${t}|${b}|${args}"
        done
      done
    fi
  done
} >"$OUT_PATH"

echo "wrote: $OUT_PATH"
