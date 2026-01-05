#!/usr/bin/env bash
# Setup BATS testing framework for zosia
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR="$TESTS_DIR/.bats"

echo "Setting up BATS testing framework..."

# Clone BATS core if not present
if [[ ! -d "$BATS_DIR/bats-core" ]]; then
  echo "Installing bats-core..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR/bats-core"
fi

# Clone BATS support libraries
if [[ ! -d "$BATS_DIR/bats-support" ]]; then
  echo "Installing bats-support..."
  git clone --depth 1 https://github.com/bats-core/bats-support.git "$BATS_DIR/bats-support"
fi

if [[ ! -d "$BATS_DIR/bats-assert" ]]; then
  echo "Installing bats-assert..."
  git clone --depth 1 https://github.com/bats-core/bats-assert.git "$BATS_DIR/bats-assert"
fi

if [[ ! -d "$BATS_DIR/bats-file" ]]; then
  echo "Installing bats-file..."
  git clone --depth 1 https://github.com/bats-core/bats-file.git "$BATS_DIR/bats-file"
fi

echo "BATS setup complete!"
echo ""
echo "Run tests with:"
echo "  $BATS_DIR/bats-core/bin/bats $TESTS_DIR/unit/"
echo "  $BATS_DIR/bats-core/bin/bats $TESTS_DIR/integration/"
echo ""
echo "Or use the test runner:"
echo "  ./tests/run-tests.sh"
