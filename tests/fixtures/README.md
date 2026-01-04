# Test Fixtures

This directory contains test fixtures for zosia integration tests.

## Files

### tiny.gguf (placeholder)

A minimal GGUF model for testing model disk creation and detection.
This file is not committed to the repository due to size constraints.

To create a test fixture locally:

```bash
# Option 1: Download a tiny test model
# (No official tiny GGUF available yet - use smallest available)

# Option 2: Create a mock GGUF header for basic testing
# The GGUF format starts with magic bytes "GGUF" followed by version
printf 'GGUF' > tests/fixtures/tiny.gguf
```

## Usage in Tests

Integration tests that require a model file should:
1. Check if the fixture exists
2. Skip the test if not available
3. Use `skip "Test fixture not available"` in BATS

Example:
```bash
@test "model disk creation works" {
  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  if [[ ! -f "$fixture" ]]; then
    skip "Test fixture not available"
  fi
  # ... test code ...
}
```
