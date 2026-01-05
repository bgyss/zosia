# Test Fixtures

This directory contains test fixtures for zosia integration tests.

## Files

### tiny.gguf

A minimal 24-byte GGUF file with valid headers but no model data.
Used for testing model disk creation without storing large model files.

**Format:**
- Magic: "GGUF" (4 bytes)
- Version: 3 (uint32 LE, 4 bytes)
- Tensor count: 0 (uint64 LE, 8 bytes)
- Metadata KV count: 0 (uint64 LE, 8 bytes)

**Regenerating:**
```bash
./tests/fixtures/generate-tiny-gguf.sh
```

### generate-tiny-gguf.sh

Script to regenerate the tiny.gguf fixture.

## Usage in Tests

```bash
@test "model disk creation works with tiny fixture" {
  skip_if_no_e2fsprogs

  local fixture="$TESTS_DIR/fixtures/tiny.gguf"
  local tmp_img
  tmp_img=$(mktemp)
  trap "rm -f '$tmp_img'" RETURN

  run "$ROOT_DIR/scripts/make-model-disk.sh" "$fixture" --out "$tmp_img"
  assert_success
}
```

## CI Considerations

The tiny.gguf fixture is committed to the repository (24 bytes).
Model disk creation tests require e2fsprogs and are skipped if unavailable.
