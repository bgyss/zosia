# Testing Guide

This document describes the testing infrastructure for zosia.

## Overview

Zosia uses a multi-layered testing approach:

| Layer | Framework | Location | CI Status |
|-------|-----------|----------|-----------|
| Unit Tests | BATS | `tests/unit/` | ✅ Runs on every push |
| Integration Tests | BATS | `tests/integration/` | ✅ Runs after build |
| Smoke Boot | Bash/QEMU | `scripts/ci/smoke-boot.sh` | ✅ Runs after build |
| Boot Mode Tests | Bash/QEMU | `scripts/ci/boot-mode-test.sh` | ✅ Runs after build |
| Performance Tests | Bash/QEMU | `scripts/ci/perf-boot.sh` | Manual |

## Quick Start

```bash
# Setup BATS framework (first time only)
./tests/setup-bats.sh

# Run all tests
./tests/run-tests.sh

# Run only unit tests
./tests/run-tests.sh unit

# Run only integration tests (requires build artifacts)
./tests/run-tests.sh integration

# Run with verbose output
./tests/run-tests.sh -v all
```

## Test Structure

```
tests/
├── setup-bats.sh       # Install BATS framework
├── run-tests.sh        # Main test runner
├── test_helper.bash    # Common test utilities
├── .gitignore          # Ignore BATS installation
├── unit/               # Unit tests (no external deps)
│   ├── init_flags.bats # Boot flag parsing tests
│   └── scripts.bats    # Script validation tests
├── integration/        # Integration tests (require QEMU)
│   ├── boot.bats       # Boot functionality tests
│   └── error_paths.bats # Error handling tests
└── fixtures/           # Test data files
    └── README.md       # Fixture documentation
```

## Unit Tests

Unit tests validate code logic without external dependencies.

### init_flags.bats

Tests boot flag parsing logic from `initramfs/init`:

- Boolean flags: `zosia.ci=1`, `zosia.diag=1`, `zosia.selftest=1`, etc.
- Value flags: `zosia.perf.tokens=N`, `zosia.llama_threads=N`, etc.
- Edge cases: empty cmdline, multiple flags, invalid values

### scripts.bats

Tests shell script structure and validity:

- Script existence and permissions
- Shebang and safety flags (`set -euo pipefail`)
- Required functions and markers
- Version file exports

## Integration Tests

Integration tests require build artifacts and QEMU.

### boot.bats

Tests actual boot functionality:

- Build artifact validation (size, format)
- Smoke boot with various flags
- Diagnostic and selftest modes
- Error handling (missing model, etc.)

### error_paths.bats

Tests error handling:

- Missing dependencies
- Missing build artifacts
- Invalid configurations
- Graceful shutdown on errors

## CI Workflow

The GitHub Actions workflow runs tests in stages:

```
unit-tests
    ↓
smoke-boot-aarch64 (build + boot)
    ↓
┌───────────────────┐
│                   │
integration-tests   boot-modes
```

### Jobs

1. **unit-tests**: Fast tests, no build required
2. **smoke-boot-aarch64**: Build and basic boot test
3. **integration-tests**: Full BATS integration suite
4. **boot-modes**: Test all boot modes (ci, diag, selftest)

## Writing Tests

### Unit Test Example

```bash
#!/usr/bin/env bats

setup() {
  load '../test_helper'
  load_bats_libs
}

@test "description of what is tested" {
  # Arrange
  local input="some input"

  # Act
  run some_function "$input"

  # Assert
  assert_success
  assert_output --partial "expected"
}
```

### Integration Test Example

```bash
@test "boot mode works correctly" {
  skip_if_no_qemu
  skip_if_no_artifacts

  run_qemu_test "zosia.diag=1" 30

  assert qemu_output_contains "zosia: diag"
}
```

### Helper Functions

The `test_helper.bash` provides:

- `load_bats_libs`: Load BATS assertion libraries
- `parse_boot_flags`: Parse cmdline flags (mimics init script)
- `check_build_artifacts`: Verify kernel/initramfs exist
- `validate_artifact_sizes`: Check artifact sizes
- `run_qemu_test`: Boot QEMU and capture output
- `qemu_output_contains`: Check QEMU output

## Running Specific Tests

```bash
# Run a specific test file
./tests/.bats/bats-core/bin/bats tests/unit/init_flags.bats

# Run tests matching a pattern
./tests/.bats/bats-core/bin/bats tests/unit/ --filter "parse zosia.ci"

# Run with TAP output
./tests/.bats/bats-core/bin/bats tests/unit/ --tap
```

## Smoke Boot Test

The smoke boot test validates basic functionality:

```bash
./scripts/ci/smoke-boot.sh
```

This script:
1. Validates build artifacts (size, format)
2. Boots QEMU with `zosia.ci=1`
3. Checks for `zosia: init` marker
4. Verifies clean shutdown

## Boot Mode Tests

Test specific boot modes:

```bash
# Test CI mode
./scripts/ci/boot-mode-test.sh ci

# Test diagnostic mode
./scripts/ci/boot-mode-test.sh diag

# Test selftest mode
./scripts/ci/boot-mode-test.sh selftest
```

## Performance Testing

Performance tests are run manually:

```bash
# Basic performance test (requires model disk)
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh

# With custom parameters
PERF_THREADS=4 PERF_TOKENS=256 ./scripts/ci/perf-boot.sh
```

See `CLAUDE.md` for detailed performance testing documentation.

## Test Coverage Summary

| Component | Coverage | Notes |
|-----------|----------|-------|
| Boot flag parsing | High | All flags tested with edge cases |
| Script structure | High | Permissions, shebangs, safety flags |
| Build artifacts | Medium | Size and format validation |
| Boot modes | High | CI, diag, selftest, stub |
| Error paths | Medium | Missing deps, missing artifacts |
| Model disk | Low | Requires fixture (not in repo) |
| Performance | Low | Manual testing only |

## Troubleshooting

### BATS not found

```bash
./tests/setup-bats.sh
```

### Tests skip due to missing QEMU

```bash
# Ubuntu/Debian
sudo apt-get install qemu-system-arm

# macOS
brew install qemu
```

### Tests skip due to missing artifacts

```bash
./scripts/build-buildroot.sh
```

### Integration tests timeout

Increase the timeout:
```bash
TIMEOUT_SECS=60 ./tests/run-tests.sh integration
```
