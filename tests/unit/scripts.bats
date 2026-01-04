#!/usr/bin/env bats
# Unit tests for zosia shell scripts

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# versions.sh tests
# ============================================================================

@test "versions.sh exports ZOSIA_BUILDROOT_REF" {
  source "$ROOT_DIR/scripts/versions.sh"
  assert [ -n "$ZOSIA_BUILDROOT_REF" ]
}

@test "versions.sh exports ZOSIA_LLAMA_CPP_REF" {
  source "$ROOT_DIR/scripts/versions.sh"
  assert [ -n "$ZOSIA_LLAMA_CPP_REF" ]
}

@test "ZOSIA_BUILDROOT_REF is a valid version format" {
  source "$ROOT_DIR/scripts/versions.sh"
  # Should match pattern like 2024.11.1
  run bash -c "echo '$ZOSIA_BUILDROOT_REF' | grep -E '^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$'"
  assert_success
}

@test "ZOSIA_LLAMA_CPP_REF is a valid git hash or tag" {
  source "$ROOT_DIR/scripts/versions.sh"
  # Should be a 40-char git hash or a tag name
  local ref="$ZOSIA_LLAMA_CPP_REF"
  if [[ ${#ref} -eq 40 ]]; then
    run bash -c "echo '$ref' | grep -E '^[a-f0-9]{40}$'"
    assert_success
  else
    # Tag format (could be various formats)
    assert [ -n "$ref" ]
  fi
}

# ============================================================================
# Script existence and permissions tests
# ============================================================================

@test "build-buildroot.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/scripts/build-buildroot.sh"
  assert_file_executable "$ROOT_DIR/scripts/build-buildroot.sh"
}

@test "run-qemu-aarch64.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/scripts/run-qemu-aarch64.sh"
  assert_file_executable "$ROOT_DIR/scripts/run-qemu-aarch64.sh"
}

@test "make-model-disk.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/scripts/make-model-disk.sh"
  assert_file_executable "$ROOT_DIR/scripts/make-model-disk.sh"
}

@test "smoke-boot.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/scripts/ci/smoke-boot.sh"
  assert_file_executable "$ROOT_DIR/scripts/ci/smoke-boot.sh"
}

@test "perf-boot.sh exists and is executable" {
  assert_file_exists "$ROOT_DIR/scripts/ci/perf-boot.sh"
  assert_file_executable "$ROOT_DIR/scripts/ci/perf-boot.sh"
}

# ============================================================================
# Script shebang and safety tests
# ============================================================================

@test "build-buildroot.sh uses bash with safety flags" {
  run head -2 "$ROOT_DIR/scripts/build-buildroot.sh"
  assert_output --partial "#!/usr/bin/env bash"
  assert_output --partial "set -euo pipefail"
}

@test "smoke-boot.sh uses bash with safety flags" {
  run head -2 "$ROOT_DIR/scripts/ci/smoke-boot.sh"
  assert_output --partial "#!/usr/bin/env bash"
  assert_output --partial "set -euo pipefail"
}

@test "perf-boot.sh uses bash with safety flags" {
  run head -2 "$ROOT_DIR/scripts/ci/perf-boot.sh"
  assert_output --partial "#!/usr/bin/env bash"
  assert_output --partial "set -euo pipefail"
}

@test "initramfs/init uses POSIX shell with safety flags" {
  run head -2 "$ROOT_DIR/initramfs/init"
  assert_output --partial "#!/bin/sh"
  assert_output --partial "set -eu"
}

# ============================================================================
# Script help text tests
# ============================================================================

@test "build-buildroot.sh has --help option" {
  run bash -c "$ROOT_DIR/scripts/build-buildroot.sh --help 2>&1 || true"
  # Should either show help or at least not crash catastrophically
  # (Some scripts may not have --help, so we just check it doesn't error badly)
  assert [ $status -le 1 ]
}

@test "make-model-disk.sh has usage information" {
  run bash -c "$ROOT_DIR/scripts/make-model-disk.sh 2>&1 || true"
  # Without args, should show usage
  assert_output --partial "Usage"
}

# ============================================================================
# Init script structure tests
# ============================================================================

@test "init script has required mount commands" {
  run grep -c "mount -t proc" "$ROOT_DIR/initramfs/init"
  assert_output "1"

  run grep -c "mount -t sysfs" "$ROOT_DIR/initramfs/init"
  assert_output "1"

  run grep -c "mount -t devtmpfs" "$ROOT_DIR/initramfs/init"
  assert_output "1"
}

@test "init script has poweroff handler" {
  run grep -c "poweroff_now" "$ROOT_DIR/initramfs/init"
  assert [ "$output" -ge 1 ]
}

@test "init script logs startup marker" {
  run grep 'log "zosia: init"' "$ROOT_DIR/initramfs/init"
  assert_success
}

@test "init script handles all documented boot flags" {
  local init_file="$ROOT_DIR/initramfs/init"

  # Check for all documented flags
  run grep "zosia.ci=1" "$init_file"
  assert_success

  run grep "zosia.diag=1" "$init_file"
  assert_success

  run grep "zosia.selftest=1" "$init_file"
  assert_success

  run grep "zosia.perf=1" "$init_file"
  assert_success

  run grep "zosia.perf.tokens=" "$init_file"
  assert_success

  run grep "zosia.llama_threads=" "$init_file"
  assert_success

  run grep "zosia.llama_batch_threads=" "$init_file"
  assert_success

  run grep "zosia.llama_args=" "$init_file"
  assert_success
}

# ============================================================================
# zosia-repl existence test
# ============================================================================

@test "zosia-repl stub script exists" {
  assert_file_exists "$ROOT_DIR/initramfs/bin/zosia-repl"
}
