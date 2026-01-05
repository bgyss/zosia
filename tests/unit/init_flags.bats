#!/usr/bin/env bats
# Unit tests for initramfs/init boot flag parsing

setup() {
  load '../test_helper'
  load_bats_libs
}

# ============================================================================
# Boolean flag parsing tests
# ============================================================================

@test "parse zosia.ci=1 flag" {
  parse_boot_flags "console=ttyAMA0 zosia.ci=1"
  assert_equal "$ZOSIA_CI" "1"
}

@test "zosia.ci defaults to 0 when not present" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_CI" "0"
}

@test "parse zosia.diag=1 flag" {
  parse_boot_flags "console=ttyAMA0 zosia.diag=1"
  assert_equal "$ZOSIA_DIAG" "1"
}

@test "zosia.diag defaults to 0 when not present" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_DIAG" "0"
}

@test "parse zosia.selftest=1 flag" {
  parse_boot_flags "console=ttyAMA0 zosia.selftest=1"
  assert_equal "$ZOSIA_SELFTEST" "1"
}

@test "zosia.selftest defaults to 0 when not present" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_SELFTEST" "0"
}

@test "parse zosia.perf=1 flag" {
  parse_boot_flags "console=ttyAMA0 zosia.perf=1"
  assert_equal "$ZOSIA_PERF" "1"
}

@test "zosia.perf defaults to 0 when not present" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_PERF" "0"
}

@test "parse zosia.allow_llama_run=1 flag" {
  parse_boot_flags "console=ttyAMA0 zosia.allow_llama_run=1"
  assert_equal "$ZOSIA_ALLOW_LLAMARUN" "1"
}

@test "zosia.allow_llama_run defaults to 0 when not present" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_ALLOW_LLAMARUN" "0"
}

# ============================================================================
# Value flag parsing tests
# ============================================================================

@test "parse zosia.perf.tokens value" {
  parse_boot_flags "console=ttyAMA0 zosia.perf.tokens=128"
  assert_equal "$ZOSIA_PERF_TOKENS" "128"
}

@test "zosia.perf.tokens defaults to 64" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_PERF_TOKENS" "64"
}

@test "parse zosia.llama_threads value" {
  parse_boot_flags "console=ttyAMA0 zosia.llama_threads=8"
  assert_equal "$ZOSIA_LLAMA_THREADS" "8"
}

@test "zosia.llama_threads defaults to empty" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_LLAMA_THREADS" ""
}

@test "parse zosia.llama_batch_threads value" {
  parse_boot_flags "console=ttyAMA0 zosia.llama_batch_threads=4"
  assert_equal "$ZOSIA_LLAMA_BATCH_THREADS" "4"
}

@test "zosia.llama_batch_threads defaults to empty" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_LLAMA_BATCH_THREADS" ""
}

@test "parse zosia.llama_args value" {
  parse_boot_flags "console=ttyAMA0 zosia.llama_args=-c,2048,-b,256"
  assert_equal "$ZOSIA_LLAMA_ARGS" "-c,2048,-b,256"
}

@test "zosia.llama_args defaults to empty" {
  parse_boot_flags "console=ttyAMA0"
  assert_equal "$ZOSIA_LLAMA_ARGS" ""
}

# ============================================================================
# Multiple flags combined
# ============================================================================

@test "parse multiple boolean flags together" {
  parse_boot_flags "console=ttyAMA0 zosia.ci=1 zosia.diag=1 zosia.perf=1"
  assert_equal "$ZOSIA_CI" "1"
  assert_equal "$ZOSIA_DIAG" "1"
  assert_equal "$ZOSIA_PERF" "1"
}

@test "parse mixed boolean and value flags" {
  parse_boot_flags "console=ttyAMA0 zosia.perf=1 zosia.perf.tokens=256 zosia.llama_threads=4"
  assert_equal "$ZOSIA_PERF" "1"
  assert_equal "$ZOSIA_PERF_TOKENS" "256"
  assert_equal "$ZOSIA_LLAMA_THREADS" "4"
}

@test "flag order does not matter" {
  parse_boot_flags "zosia.llama_threads=4 console=ttyAMA0 zosia.ci=1"
  assert_equal "$ZOSIA_CI" "1"
  assert_equal "$ZOSIA_LLAMA_THREADS" "4"
}

# ============================================================================
# Edge cases
# ============================================================================

@test "empty cmdline parses with defaults" {
  parse_boot_flags ""
  assert_equal "$ZOSIA_CI" "0"
  assert_equal "$ZOSIA_DIAG" "0"
  assert_equal "$ZOSIA_PERF_TOKENS" "64"
}

@test "flag with extra spaces is parsed correctly" {
  parse_boot_flags "console=ttyAMA0  zosia.ci=1  zosia.diag=1"
  assert_equal "$ZOSIA_CI" "1"
  assert_equal "$ZOSIA_DIAG" "1"
}

@test "similar flag names don't conflict (zosia.ci vs zosia.ci_mode)" {
  # Only exact match should work
  parse_boot_flags "console=ttyAMA0 zosia.ci_mode=1"
  assert_equal "$ZOSIA_CI" "0"  # Should not match
}

@test "flag value with equals sign is handled" {
  # e.g., zosia.llama_args=-c=2048 (unusual but possible)
  parse_boot_flags "console=ttyAMA0 zosia.llama_args=-c=2048"
  assert_equal "$ZOSIA_LLAMA_ARGS" "-c=2048"
}

@test "numeric token count is preserved" {
  parse_boot_flags "zosia.perf.tokens=9999"
  assert_equal "$ZOSIA_PERF_TOKENS" "9999"
}

@test "zero value for tokens is valid" {
  parse_boot_flags "zosia.perf.tokens=0"
  assert_equal "$ZOSIA_PERF_TOKENS" "0"
}
