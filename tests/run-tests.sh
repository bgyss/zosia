#!/usr/bin/env bash
# Run all zosia tests
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
BATS_DIR="$TESTS_DIR/.bats"
BATS="$BATS_DIR/bats-core/bin/bats"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TEST_TYPE]

Run zosia test suites.

TEST_TYPE:
  unit          Run unit tests only
  integration   Run integration tests only
  all           Run all tests (default)

OPTIONS:
  -h, --help    Show this help message
  -v, --verbose Enable verbose output
  -s, --setup   Setup BATS framework first

Examples:
  $(basename "$0")              # Run all tests
  $(basename "$0") unit         # Run unit tests only
  $(basename "$0") -s all       # Setup BATS and run all tests
EOF
}

setup_bats() {
  if [[ ! -x "$BATS" ]]; then
    echo -e "${YELLOW}Setting up BATS framework...${NC}"
    "$TESTS_DIR/setup-bats.sh"
  fi
}

run_unit_tests() {
  echo -e "${YELLOW}Running unit tests...${NC}"
  if [[ -d "$TESTS_DIR/unit" ]] && ls "$TESTS_DIR/unit"/*.bats >/dev/null 2>&1; then
    "$BATS" "$TESTS_DIR/unit/"
  else
    echo "No unit tests found"
  fi
}

run_integration_tests() {
  echo -e "${YELLOW}Running integration tests...${NC}"
  if [[ -d "$TESTS_DIR/integration" ]] && ls "$TESTS_DIR/integration"/*.bats >/dev/null 2>&1; then
    "$BATS" "$TESTS_DIR/integration/"
  else
    echo "No integration tests found"
  fi
}

# Parse arguments
VERBOSE=0
DO_SETUP=0
TEST_TYPE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -s|--setup)
      DO_SETUP=1
      shift
      ;;
    unit|integration|all)
      TEST_TYPE="$1"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Export for BATS
export ROOT_DIR
export TESTS_DIR

# Setup if requested or needed
if [[ "$DO_SETUP" -eq 1 ]] || [[ ! -x "$BATS" ]]; then
  setup_bats
fi

# Check BATS is available
if [[ ! -x "$BATS" ]]; then
  echo -e "${RED}BATS not found. Run with -s to setup.${NC}" >&2
  exit 1
fi

# Add verbose flag if requested
if [[ "$VERBOSE" -eq 1 ]]; then
  BATS="$BATS --verbose-run"
fi

# Run tests
FAILED=0

case "$TEST_TYPE" in
  unit)
    run_unit_tests || FAILED=1
    ;;
  integration)
    run_integration_tests || FAILED=1
    ;;
  all)
    run_unit_tests || FAILED=1
    echo ""
    run_integration_tests || FAILED=1
    ;;
esac

if [[ "$FAILED" -eq 0 ]]; then
  echo -e "\n${GREEN}All tests passed!${NC}"
else
  echo -e "\n${RED}Some tests failed!${NC}"
  exit 1
fi
