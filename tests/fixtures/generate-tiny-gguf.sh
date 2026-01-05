#!/usr/bin/env bash
# Generate a minimal valid GGUF file for testing
# This creates a ~24 byte file with valid GGUF headers but no actual model data
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$FIXTURE_DIR/tiny.gguf}"

# GGUF format:
# - Magic: "GGUF" (4 bytes)
# - Version: uint32 LE (4 bytes) - version 3
# - Tensor count: uint64 LE (8 bytes) - 0 tensors
# - Metadata KV count: uint64 LE (8 bytes) - 0 metadata

# Create the header using printf with hex escapes
{
  # Magic: GGUF
  printf 'GGUF'
  # Version: 3 (uint32 little-endian)
  printf '\x03\x00\x00\x00'
  # Tensor count: 0 (uint64 little-endian)
  printf '\x00\x00\x00\x00\x00\x00\x00\x00'
  # Metadata KV count: 0 (uint64 little-endian)
  printf '\x00\x00\x00\x00\x00\x00\x00\x00'
} > "$OUTPUT"

echo "Created minimal GGUF fixture: $OUTPUT ($(wc -c < "$OUTPUT") bytes)"
