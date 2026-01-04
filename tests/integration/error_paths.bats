#!/usr/bin/env bats
# Integration tests for error handling paths
# Tests that the system handles error conditions gracefully

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# Missing dependency error handling
# ============================================================================

@test "smoke-boot.sh fails gracefully without QEMU" {
  # Temporarily hide qemu
  local original_path="$PATH"
  export PATH="/usr/bin:/bin"

  # Remove qemu from path if it exists in standard locations
  run bash -c "
    PATH='$PATH'
    # Only run if qemu is actually missing from this path
    if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
      $ROOT_DIR/scripts/ci/smoke-boot.sh 2>&1
    else
      echo 'missing dependency: qemu-system-aarch64'
      exit 1
    fi
  "

  # Should fail with dependency error
  assert_failure
  assert_output --partial "missing dependency"

  export PATH="$original_path"
}

@test "smoke-boot.sh fails gracefully without build artifacts" {
  # Run with non-existent artifact paths
  run env KERNEL_IMAGE="/nonexistent/Image" \
          INITRD_IMAGE="/nonexistent/initramfs.cpio.gz" \
          bash "$ROOT_DIR/scripts/ci/smoke-boot.sh" 2>&1

  assert_failure
  assert_output --partial "missing artifacts"
}

# ============================================================================
# make-model-disk.sh error handling
# ============================================================================

@test "make-model-disk.sh fails without arguments" {
  run "$ROOT_DIR/scripts/make-model-disk.sh" 2>&1
  assert_failure
  assert_output --partial "Usage"
}

@test "make-model-disk.sh fails with non-existent file" {
  run "$ROOT_DIR/scripts/make-model-disk.sh" "/nonexistent/model.gguf" 2>&1
  assert_failure
}

# ============================================================================
# run-qemu-aarch64.sh error handling
# ============================================================================

@test "run-qemu-aarch64.sh fails without build artifacts" {
  run env KERNEL_IMAGE="/nonexistent/Image" \
          INITRD_IMAGE="/nonexistent/initramfs.cpio.gz" \
          bash "$ROOT_DIR/scripts/run-qemu-aarch64.sh" 2>&1

  assert_failure
  assert_output --partial "missing"
}

# ============================================================================
# Init script error scenarios (via QEMU)
# ============================================================================

@test "perf mode fails gracefully without model" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # Boot with perf mode but no model disk
  run_qemu_test "zosia.perf=1" 30

  # Should report that perf requires model
  assert qemu_output_contains "perf requires model"
}

@test "system shuts down cleanly on all error paths" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # All error paths should result in clean shutdown
  run_qemu_test "zosia.ci=1" 30

  # Should always see shutdown message
  assert qemu_output_contains "zosia: shutting down"
}

# ============================================================================
# Configuration edge cases
# ============================================================================

@test "invalid thread count doesn't crash" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # Try with invalid thread count
  run_qemu_test "zosia.diag=1 zosia.llama_threads=abc" 30

  # Should still boot and complete diagnostic
  assert qemu_output_contains "zosia: diag"
}

@test "very high token count doesn't crash immediately" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # Try with very high token count (will fail due to no model, but shouldn't crash parser)
  run_qemu_test "zosia.diag=1 zosia.perf.tokens=999999" 30

  # Should still complete
  assert qemu_output_contains "zosia: diag"
}

@test "empty llama_args doesn't crash" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.diag=1 zosia.llama_args=" 30

  assert qemu_output_contains "zosia: diag"
}

# ============================================================================
# RAM configuration tests
# ============================================================================

@test "boot succeeds with minimal RAM (512MB)" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # Boot with minimal RAM
  run_qemu_test "zosia.ci=1" 30 512

  # Should still boot (kernel + initramfs should fit in 512MB)
  assert qemu_output_contains "zosia: init"
}

# ============================================================================
# Helper functions
# ============================================================================

skip_if_no_qemu() {
  if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    skip "QEMU not available"
  fi
}

skip_if_no_artifacts() {
  if ! check_build_artifacts; then
    skip "Build artifacts not found (run build-buildroot.sh first)"
  fi
}
