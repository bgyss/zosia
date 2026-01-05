#!/usr/bin/env bats
# Unit tests for test fixtures

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# tiny.gguf fixture tests
# ============================================================================

@test "tiny.gguf fixture exists" {
  assert_file_exists "$TESTS_DIR/fixtures/tiny.gguf"
}

@test "tiny.gguf has correct size (24 bytes)" {
  local size
  size=$(wc -c < "$TESTS_DIR/fixtures/tiny.gguf")
  assert_equal "$size" "24"
}

@test "tiny.gguf has GGUF magic header" {
  local magic
  magic=$(head -c 4 "$TESTS_DIR/fixtures/tiny.gguf")
  assert_equal "$magic" "GGUF"
}

@test "tiny.gguf has version 3" {
  # Read bytes 5-8 (version field) and check it's 3 in little-endian
  local version_bytes
  version_bytes=$(xxd -p -s 4 -l 4 "$TESTS_DIR/fixtures/tiny.gguf" 2>/dev/null || od -A n -t x1 -j 4 -N 4 "$TESTS_DIR/fixtures/tiny.gguf" | tr -d ' ')
  # Version 3 in little-endian hex is 03000000
  assert_equal "$version_bytes" "03000000"
}

# ============================================================================
# generate-tiny-gguf.sh tests
# ============================================================================

@test "generate-tiny-gguf.sh exists and is executable" {
  assert_file_exists "$TESTS_DIR/fixtures/generate-tiny-gguf.sh"
  assert_file_executable "$TESTS_DIR/fixtures/generate-tiny-gguf.sh"
}

@test "generate-tiny-gguf.sh creates valid fixture" {
  local tmp_gguf
  tmp_gguf=$(mktemp)
  trap "rm -f '$tmp_gguf'" RETURN

  run "$TESTS_DIR/fixtures/generate-tiny-gguf.sh" "$tmp_gguf"
  assert_success

  # Check the generated file
  local magic
  magic=$(head -c 4 "$tmp_gguf")
  assert_equal "$magic" "GGUF"

  local size
  size=$(wc -c < "$tmp_gguf")
  assert_equal "$size" "24"
}
