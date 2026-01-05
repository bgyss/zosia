#!/usr/bin/env bats
# Integration tests for model disk creation
# Requires e2fsprogs (mkfs.ext4, debugfs)

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# Helper functions
# ============================================================================

skip_if_no_e2fsprogs() {
  if ! command -v mkfs.ext4 >/dev/null 2>&1; then
    skip "mkfs.ext4 not available (install e2fsprogs)"
  fi
  if ! command -v debugfs >/dev/null 2>&1; then
    skip "debugfs not available (install e2fsprogs)"
  fi
}

skip_if_no_fixture() {
  if [[ ! -f "$TESTS_DIR/fixtures/tiny.gguf" ]]; then
    skip "tiny.gguf fixture not found"
  fi
}

# ============================================================================
# Model disk creation tests
# ============================================================================

@test "make-model-disk.sh creates disk image from tiny fixture" {
  skip_if_no_e2fsprogs
  skip_if_no_fixture

  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  local tmp_img
  tmp_img=$(mktemp --suffix=.img)
  trap "rm -f '$tmp_img'" RETURN

  run "$ROOT_DIR/scripts/make-model-disk.sh" "$fixture" --out "$tmp_img"
  assert_success

  # Verify the image was created
  assert_file_exists "$tmp_img"

  # Verify it's a valid ext4 image
  run file "$tmp_img"
  assert_output --partial "ext4 filesystem"
}

@test "model disk contains model.gguf file" {
  skip_if_no_e2fsprogs
  skip_if_no_fixture

  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  local tmp_img
  tmp_img=$(mktemp --suffix=.img)
  trap "rm -f '$tmp_img'" RETURN

  "$ROOT_DIR/scripts/make-model-disk.sh" "$fixture" --out "$tmp_img"

  # Check that model.gguf exists in the image using debugfs
  run debugfs -R "stat /model.gguf" "$tmp_img" 2>/dev/null
  assert_success
}

@test "model disk image has correct model file size" {
  skip_if_no_e2fsprogs
  skip_if_no_fixture

  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  local fixture_size
  fixture_size=$(wc -c < "$fixture")

  local tmp_img
  tmp_img=$(mktemp --suffix=.img)
  trap "rm -f '$tmp_img'" RETURN

  "$ROOT_DIR/scripts/make-model-disk.sh" "$fixture" --out "$tmp_img"

  # Extract file size from debugfs stat output
  local img_size
  img_size=$(debugfs -R "stat /model.gguf" "$tmp_img" 2>/dev/null | grep -oP 'Size: \K\d+' || echo "0")

  assert_equal "$img_size" "$fixture_size"
}

@test "make-model-disk.sh respects --extra-mib option" {
  skip_if_no_e2fsprogs
  skip_if_no_fixture

  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  local tmp_img
  tmp_img=$(mktemp --suffix=.img)
  trap "rm -f '$tmp_img'" RETURN

  # Create with minimal extra space
  run "$ROOT_DIR/scripts/make-model-disk.sh" "$fixture" --out "$tmp_img" --extra-mib 1
  assert_success

  # Image should exist and be at least 1 MiB
  local size
  size=$(stat -c%s "$tmp_img" 2>/dev/null || stat -f%z "$tmp_img" 2>/dev/null)
  assert [ "$size" -ge 1048576 ]  # 1 MiB
}

@test "make-model-disk.sh fails with non-existent file" {
  run "$ROOT_DIR/scripts/make-model-disk.sh" "/nonexistent/model.gguf" --out "/tmp/test.img"
  assert_failure
}

@test "make-model-disk.sh fails without arguments" {
  run "$ROOT_DIR/scripts/make-model-disk.sh"
  # Exit 0 for help, but should show usage
  assert_output --partial "usage:"
}
