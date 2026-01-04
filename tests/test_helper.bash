# Common test helper functions for zosia tests
# Source this file in your BATS tests

# Directories
export TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export ROOT_DIR="${ROOT_DIR:-$(cd "$TESTS_DIR/.." && pwd)}"
export BATS_LIB_DIR="$TESTS_DIR/.bats"

# Load BATS libraries
load_bats_libs() {
  load "$BATS_LIB_DIR/bats-support/load"
  load "$BATS_LIB_DIR/bats-assert/load"
  if [[ -d "$BATS_LIB_DIR/bats-file" ]]; then
    load "$BATS_LIB_DIR/bats-file/load"
  fi
}

# Parse boot flags from a cmdline string (mimics init script logic)
# Usage: parse_boot_flags "console=ttyAMA0 zosia.ci=1"
# Sets: ZOSIA_CI, ZOSIA_DIAG, ZOSIA_SELFTEST, ZOSIA_PERF, etc.
parse_boot_flags() {
  local cmdline="$1"

  # Initialize defaults
  ZOSIA_CI=0
  ZOSIA_DIAG=0
  ZOSIA_SELFTEST=0
  ZOSIA_PERF=0
  ZOSIA_ALLOW_LLAMARUN=0
  ZOSIA_PERF_TOKENS=64
  ZOSIA_LLAMA_THREADS=""
  ZOSIA_LLAMA_BATCH_THREADS=""
  ZOSIA_LLAMA_ARGS=""

  # Parse boolean flags
  case " $cmdline " in
    *" zosia.ci=1 "*) ZOSIA_CI=1 ;;
  esac
  case " $cmdline " in
    *" zosia.diag=1 "*) ZOSIA_DIAG=1 ;;
  esac
  case " $cmdline " in
    *" zosia.selftest=1 "*) ZOSIA_SELFTEST=1 ;;
  esac
  case " $cmdline " in
    *" zosia.perf=1 "*) ZOSIA_PERF=1 ;;
  esac
  case " $cmdline " in
    *" zosia.allow_llama_run=1 "*) ZOSIA_ALLOW_LLAMARUN=1 ;;
  esac

  # Parse value flags
  for arg in $cmdline; do
    case "$arg" in
      zosia.perf.tokens=*) ZOSIA_PERF_TOKENS="${arg#zosia.perf.tokens=}" ;;
      zosia.llama_threads=*) ZOSIA_LLAMA_THREADS="${arg#zosia.llama_threads=}" ;;
      zosia.llama_batch_threads=*) ZOSIA_LLAMA_BATCH_THREADS="${arg#zosia.llama_batch_threads=}" ;;
      zosia.llama_args=*) ZOSIA_LLAMA_ARGS="${arg#zosia.llama_args=}" ;;
    esac
  done

  # Export for test assertions
  export ZOSIA_CI ZOSIA_DIAG ZOSIA_SELFTEST ZOSIA_PERF ZOSIA_ALLOW_LLAMARUN
  export ZOSIA_PERF_TOKENS ZOSIA_LLAMA_THREADS ZOSIA_LLAMA_BATCH_THREADS ZOSIA_LLAMA_ARGS
}

# Check if build artifacts exist
check_build_artifacts() {
  local kernel="$ROOT_DIR/artifacts/aarch64/Image"
  local initrd="$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"

  [[ -f "$kernel" ]] && [[ -f "$initrd" ]]
}

# Validate artifact sizes (basic sanity check)
validate_artifact_sizes() {
  local kernel="$ROOT_DIR/artifacts/aarch64/Image"
  local initrd="$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"

  # Kernel should be at least 10MB
  local kernel_size
  kernel_size=$(stat -c%s "$kernel" 2>/dev/null || stat -f%z "$kernel" 2>/dev/null || echo 0)
  if [[ "$kernel_size" -lt 10000000 ]]; then
    echo "Kernel too small: $kernel_size bytes" >&2
    return 1
  fi

  # Initramfs should be at least 1MB
  local initrd_size
  initrd_size=$(stat -c%s "$initrd" 2>/dev/null || stat -f%z "$initrd" 2>/dev/null || echo 0)
  if [[ "$initrd_size" -lt 1000000 ]]; then
    echo "Initramfs too small: $initrd_size bytes" >&2
    return 1
  fi

  return 0
}

# Create a temporary mock environment for testing init script functions
create_mock_env() {
  local mock_dir
  mock_dir=$(mktemp -d)

  mkdir -p "$mock_dir/proc" "$mock_dir/sys" "$mock_dir/dev" "$mock_dir/models"

  echo "$mock_dir"
}

# Clean up mock environment
cleanup_mock_env() {
  local mock_dir="$1"
  [[ -d "$mock_dir" ]] && rm -rf "$mock_dir"
}

# Check if QEMU is available
qemu_available() {
  command -v qemu-system-aarch64 >/dev/null 2>&1
}

# Run QEMU with specified boot flags and capture output
# Usage: run_qemu_test "zosia.ci=1" 30
# Returns: output in $QEMU_OUTPUT, exit code
run_qemu_test() {
  local append_extra="${1:-zosia.ci=1}"
  local timeout_secs="${2:-30}"
  local ram_mb="${3:-1024}"

  local kernel="$ROOT_DIR/artifacts/aarch64/Image"
  local initrd="$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"

  if [[ ! -f "$kernel" ]] || [[ ! -f "$initrd" ]]; then
    echo "Build artifacts not found" >&2
    return 1
  fi

  local tmp_out
  tmp_out=$(mktemp)

  local cmd=(
    qemu-system-aarch64
    -machine virt
    -cpu max
    -m "$ram_mb"
    -smp 2
    -display none
    -serial stdio
    -monitor none
    -kernel "$kernel"
    -initrd "$initrd"
    -append "console=ttyAMA0 rdinit=/init $append_extra panic=-1"
  )

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_secs" "${cmd[@]}" > "$tmp_out" 2>&1 || true
  else
    "${cmd[@]}" > "$tmp_out" 2>&1 &
    local pid=$!
    sleep "$timeout_secs"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi

  QEMU_OUTPUT=$(cat "$tmp_out")
  rm -f "$tmp_out"

  export QEMU_OUTPUT
}

# Check for a pattern in QEMU output
qemu_output_contains() {
  local pattern="$1"
  echo "$QEMU_OUTPUT" | grep -q "$pattern"
}
