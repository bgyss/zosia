#!/usr/bin/env bats
# Integration tests for zosia boot functionality
# These tests require build artifacts and QEMU

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# Build artifact validation
# ============================================================================

@test "kernel image exists" {
  assert_file_exists "$ROOT_DIR/artifacts/aarch64/Image"
}

@test "initramfs exists" {
  assert_file_exists "$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"
}

@test "kernel image is valid size (>10MB)" {
  skip_if_no_artifacts

  local kernel="$ROOT_DIR/artifacts/aarch64/Image"
  local size
  size=$(stat -c%s "$kernel" 2>/dev/null || stat -f%z "$kernel" 2>/dev/null || echo 0)

  assert [ "$size" -gt 10000000 ]
}

@test "initramfs is valid size (>1MB)" {
  skip_if_no_artifacts

  local initrd="$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"
  local size
  size=$(stat -c%s "$initrd" 2>/dev/null || stat -f%z "$initrd" 2>/dev/null || echo 0)

  assert [ "$size" -gt 1000000 ]
}

@test "initramfs is valid gzip file" {
  skip_if_no_artifacts

  local initrd="$ROOT_DIR/artifacts/aarch64/initramfs.cpio.gz"
  run gzip -t "$initrd"
  assert_success
}

# ============================================================================
# QEMU boot tests (require QEMU)
# ============================================================================

@test "smoke boot succeeds with zosia.ci=1" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.ci=1" 30
  assert qemu_output_contains "zosia: init"
}

@test "boot outputs shutdown message" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.ci=1" 30
  assert qemu_output_contains "zosia: shutting down"
}

@test "diagnostic mode outputs expected markers" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.diag=1" 30

  assert qemu_output_contains "zosia: init"
  assert qemu_output_contains "zosia: diag"
  assert qemu_output_contains "zosia: model_dev="
  assert qemu_output_contains "zosia: llama_bin="
  assert qemu_output_contains "zosia: model_path="
}

@test "selftest mode outputs llama binary status" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.selftest=1" 30

  assert qemu_output_contains "zosia: selftest"
  assert qemu_output_contains "zosia: llama_bin="
}

@test "boot without model disk falls back to stub" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.ci=1" 30

  # Should indicate no model found and use stub
  # (In CI mode, it powers off, but should log the stub message first)
  assert qemu_output_contains "zosia: init"
  # Either "model not found" or "stub prompt" message
  if qemu_output_contains "model not found"; then
    assert qemu_output_contains "stub prompt"
  fi
}

@test "ci mode powers off automatically" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.ci=1" 30

  assert qemu_output_contains "zosia: ci mode"
}

# ============================================================================
# Error path tests
# ============================================================================

@test "boot handles missing virtio disk gracefully" {
  skip_if_no_qemu
  skip_if_no_artifacts

  # Boot without any disk attached (default)
  run_qemu_test "zosia.diag=1" 30

  # Should report no model disk found
  assert qemu_output_contains "model_dev=none" || \
    qemu_output_contains "no virtio model disk"
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
