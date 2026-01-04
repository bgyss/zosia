# CLAUDE.md

AI Assistant Development Guide for zosia

## Project Overview

**zosia** is a minimal Linux VM project that boots directly into an interactive GPT-style prompt over the serial console. It's designed to run on QEMU (AArch64) on macOS (Apple Silicon), providing a direct LLM REPL experience backed by local GGUF models via llama.cpp.

### Primary Goal
Boot a minimal Linux VM directly into a GPT prompt with no traditional shell/UI, targeting Apple Silicon with QEMU acceleration.

### Current Status
MVP complete: boots into a serial-console prompt from initramfs; if a GGUF model disk is attached, it launches `llama-cli` automatically.

## Repository Structure

```
zosia/
├── AGENTS.md              # AI agent guidelines and project decisions
├── CONTINUITY.md          # Session continuity ledger for AI agents
├── README.md              # User-facing documentation
├── CLAUDE.md              # This file - AI development guide
├── .agent/                # AI planning and execution plans
│   ├── PLANS.md          # ExecPlan template
│   └── execplans/        # Specific execution plans
├── artifacts/            # Build outputs (gitignored)
│   └── aarch64/
│       ├── Image         # Linux kernel
│       └── initramfs.cpio.gz
├── assets/               # Static assets
│   └── uefi/            # UEFI firmware files
├── buildroot/            # Buildroot integration
│   ├── buildroot-src/   # Buildroot source (gitignored)
│   ├── output/          # Build outputs (gitignored)
│   └── external/        # zosia-specific Buildroot tree
│       ├── configs/     # Defconfigs
│       ├── board/       # Board-specific files
│       └── package/     # Custom packages (llama-cpp)
├── docs/                 # MkDocs documentation
│   ├── index.md
│   ├── quickstart.md
│   ├── architecture.md
│   └── troubleshooting.md
├── initramfs/            # Initramfs overlay
│   ├── init             # Init script (PID 1)
│   └── bin/
│       └── zosia-repl   # Stub REPL when no model
├── models/              # GGUF models (gitignored)
├── scripts/             # Build and run scripts
│   ├── build-buildroot.sh
│   ├── build-llama.sh
│   ├── make-model-disk.sh
│   ├── run-qemu-aarch64.sh
│   ├── versions.sh      # Pinned versions
│   └── ci/
│       ├── smoke-boot.sh
│       ├── perf-boot.sh
│       └── gen-perf-matrix.sh
├── mkdocs.yml           # MkDocs configuration
└── tmp/                 # Temporary files
```

## Key Files and Their Purposes

### Core Configuration
- **scripts/versions.sh**: Pinned versions for reproducible builds
  - `ZOSIA_BUILDROOT_REF`: Buildroot version (currently 2024.11.1)
  - `ZOSIA_LLAMA_CPP_REF`: llama.cpp git commit hash

### Build System
- **buildroot/external/configs/zosia_aarch64_defconfig**: Main Buildroot configuration
- **buildroot/external/package/llama-cpp/**: Custom Buildroot package for llama.cpp
- **buildroot/external/board/zosia/linux.fragment**: Kernel config fragment

### Runtime
- **initramfs/init**: PID 1 init script that:
  1. Mounts /proc, /sys, /dev
  2. Mounts model disk (virtio-blk) at /models
  3. Launches llama-cli with detected model
  4. Falls back to stub REPL if no model
  5. Powers off on exit

### Boot Flags (via APPEND_EXTRA)
- `zosia.ci=1`: Boot then power off (CI mode)
- `zosia.diag=1`: Print diagnostics then power off
- `zosia.selftest=1`: Run `llama-cli --help` then power off
- `zosia.perf=1`: Run performance test then power off
- `zosia.perf.tokens=N`: Custom token count for perf tests
- `zosia.llama_threads=N`: Override thread count
- `zosia.llama_batch_threads=N`: Override batch thread count
- `zosia.llama_args=arg1,arg2`: Extra llama args (comma-separated)

## Development Workflows

### Initial Setup (macOS)

```bash
# Prerequisites
brew install qemu e2fsprogs

# Build kernel + initramfs
./scripts/build-buildroot.sh

# Create model disk (default: Phi-3.5 mini Q4_K_M)
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker

# Run VM
./scripts/run-qemu-aarch64.sh
```

### Build System

#### Buildroot Build
```bash
# Build everything (kernel + initramfs)
./scripts/build-buildroot.sh

# On macOS, this automatically uses Docker
# To disable Docker: ZOSIA_NO_DOCKER=1 ./scripts/build-buildroot.sh

# Control parallelism
ZOSIA_JOBS=8 ./scripts/build-buildroot.sh
```

**Build Artifacts:**
- `artifacts/aarch64/Image` - Linux kernel
- `artifacts/aarch64/initramfs.cpio.gz` - Initramfs with BusyBox + llama-cli

#### Model Disk Creation
```bash
# Default (Phi-3.5 mini)
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker

# Custom model
./scripts/make-model-disk.sh /path/to/model.gguf --use-docker

# Without Docker (Linux or if macOS native tools work)
./scripts/make-model-disk.sh models/model.gguf
```

**Important:** On macOS, large GGUFs may fail with "Ext2 file too big" without `--use-docker`.

### Testing

#### Smoke Test (CI)
```bash
./scripts/ci/smoke-boot.sh
# Or manually:
RAM_MB=2048 APPEND_EXTRA='zosia.ci=1' ./scripts/run-qemu-aarch64.sh
```

#### Performance Testing
```bash
# Single perf run (default profile: Phi-3.5 mini)
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh

# Phi-3.5 fast profile (128 tokens)
PERF_PROFILE=phi35_fast PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh

# Continuous tuning loop
./scripts/ci/gen-perf-matrix.sh
PERF_MATRIX_FILE=perf.matrix PERF_LOOP=1 PERF_FAIL_FAST=0 \
  PERF_RESULTS=/tmp/zosia-perf.csv PERF_LOG_DIR=/tmp/zosia-perf-logs \
  ./scripts/ci/perf-boot.sh
```

**Perf Environment Variables:**
- `PERF_THREADS`: Override llama thread count
- `PERF_BATCH_THREADS`: Override batch thread count
- `PERF_LLAMA_ARGS`: Comma-separated llama args
- `PERF_RUNS`: Number of perf runs
- `PERF_TOKENS`: Token count for generation
- `PERF_TIMEOUT`: Timeout in seconds
- `PERF_PROFILE`: `phi35_fast` (default) or `none`

#### Diagnostic Tests
```bash
# Check if llama binary is present
RAM_MB=2048 APPEND_EXTRA='zosia.selftest=1' ./scripts/run-qemu-aarch64.sh

# Check disk/model detection
RAM_MB=2048 APPEND_EXTRA='zosia.diag=1' ./scripts/run-qemu-aarch64.sh
```

### Interactive Development
```bash
# Interactive run (requires model disk)
RAM_MB=32768 ./scripts/run-qemu-aarch64.sh

# Stub mode (no model)
RAM_MB=2048 ./scripts/run-qemu-aarch64.sh

# Custom QEMU settings
QEMU_ACCEL=tcg QEMU_CPU=max ./scripts/run-qemu-aarch64.sh
```

**RAM Guidance:**
- 2048 MB: Smoke boot + stub prompt
- 32768 MB: Default, suitable for Phi-3.5 mini Q4_K_M
- Higher: Required for larger models (20B+ models need tens of GB)

## Key Conventions and Standards

### Code Style

#### Shell Scripts
- Use `#!/usr/bin/env bash` for bash scripts
- Use `#!/bin/sh` for POSIX shell scripts (initramfs)
- Always use `set -euo pipefail` in bash scripts
- Always use `set -eu` in POSIX shell scripts
- Use shellcheck-compatible patterns
- Functions should have descriptive names
- Use `local` for function-scoped variables in bash

#### Initramfs Scripts
- Must be POSIX-compliant (BusyBox ash)
- Keep dependencies minimal
- Log to `/dev/console` for visibility
- Handle missing binaries/files gracefully
- Always provide cleanup/shutdown handlers

### Documentation Standards

#### Keep Docs in Sync
When making code or behavior changes, ALWAYS update:
1. **README.md** - User-facing documentation
2. **docs/*.md** - Detailed documentation
3. **AGENTS.md** - If changing key decisions or constraints
4. **CLAUDE.md** - If changing development workflows

#### Documentation Structure
- **README.md**: Quick start, prerequisites, common commands
- **docs/quickstart.md**: Step-by-step getting started guide
- **docs/architecture.md**: Boot flow, storage layout, design decisions
- **docs/troubleshooting.md**: Common issues and solutions
- **AGENTS.md**: AI agent guidelines, project goals, constraints

### Git Workflow

#### Commit Messages
- Use conventional commit style when appropriate
- Be descriptive but concise
- Reference issues/PRs when relevant
- Keep commits atomic and focused

#### Branches
- Follow the branch naming in development requirements
- Always develop on the specified branch
- Push to the correct branch with `-u origin <branch>`

### ExecPlans for Complex Features

For complex features or significant refactors:

1. Create an ExecPlan in `.agent/execplans/####_short_name.md`
2. Use the template from `.agent/PLANS.md`
3. Fill out all sections:
   - Summary (goal, out of scope, success criteria)
   - Context (user problem, constraints)
   - Proposed Design (modules, data model, API, UX)
   - Milestones
   - Risks & Mitigations
   - Test Plan
   - Rollout / Compatibility
4. Follow the plan during implementation
5. Update the plan as implementation proceeds

## Performance Considerations

### Target Performance
- Boot time: < 5s after kernel load (excluding model mmap warmup)
- Token generation: ~20 tok/s minimum for interactive use
- Default model: Phi-3.5 mini Q4_K_M (chosen for speed)

### Optimization Guidelines
- Use QEMU acceleration on macOS: `QEMU_ACCEL=hvf`, `QEMU_CPU=host`
- Tune thread counts via `zosia.llama_threads` and `zosia.llama_batch_threads`
- Smaller models with stronger quantization for better tok/s
- Use local SSD for mmap-friendly storage
- Default Phi-3.5 profile: 6 threads, batch size 256, context 1024

### Tested Models
- **Phi-3.5 mini Q4_K_M** (default): ~20 tok/s, good interactive performance
- **gpt-oss-20b** (MXFP4): Validated but too slow for interactive use on CPU

## Common Patterns and Idioms

### Adding New Boot Flags

1. Edit `initramfs/init`:
```sh
ZOSIA_NEWFLAG=0
case " $CMDLINE " in
  *" zosia.newflag=1 "*) ZOSIA_NEWFLAG=1 ;;
esac
```

2. Use the flag:
```sh
if [ "$ZOSIA_NEWFLAG" = "1" ]; then
  # Do something
fi
```

3. Document in README.md boot flags section

### Modifying Buildroot Configuration

1. Update `buildroot/external/configs/zosia_aarch64_defconfig`
2. Rebuild: `./scripts/build-buildroot.sh`
3. Test with smoke boot: `./scripts/ci/smoke-boot.sh`

### Adding Initramfs Files

1. Add files to `initramfs/` directory structure
2. Buildroot automatically includes them via rootfs overlay
3. Rebuild: `./scripts/build-buildroot.sh`
4. Test the change

### Creating New Scripts

1. Add to `scripts/` directory
2. Use `#!/usr/bin/env bash` shebang
3. Include `set -euo pipefail`
4. Source `scripts/versions.sh` if needed:
```bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/versions.sh"
```
5. Add `--help` handling
6. Make executable: `chmod +x scripts/newscript.sh`

## Important Notes for AI Assistants

### Critical Constraints (from AGENTS.md)
1. Must run in QEMU on macOS (Apple Silicon) with UEFI
2. Keep boot time < 5s after kernel load
3. Keep userspace minimal: only what's required for the REPL
4. Keep README.md and docs/ up to date with any code or behavior changes
5. When rebuilding model disk, use: `./scripts/make-model-disk.sh ./models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker`

### Non-Goals (v1)
- Bare-metal install/boot on Mac hardware
- GUI/web UI
- Tool-calling, browsing, or networking features beyond model loading

### Before Making Changes

1. **Read existing code first** - Never propose changes without reading the file
2. **Check AGENTS.md** - Review project goals and constraints
3. **Update documentation** - Keep README.md and docs/ in sync
4. **Use ExecPlans** - For complex features, create an execution plan
5. **Test thoroughly** - Use smoke tests and perf tests

### When Rebuilding

**Default rebuild workflow:**
```bash
# 1. Build kernel + initramfs
./scripts/build-buildroot.sh

# 2. Create model disk (default Phi-3.5 mini)
./scripts/make-model-disk.sh ./models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker

# 3. Test
./scripts/ci/smoke-boot.sh
```

### Debugging Tips

1. **Enable diagnostics:**
```bash
RAM_MB=2048 APPEND_EXTRA='zosia.diag=1' ./scripts/run-qemu-aarch64.sh
```

2. **Check llama binary:**
```bash
RAM_MB=2048 APPEND_EXTRA='zosia.selftest=1' ./scripts/run-qemu-aarch64.sh
```

3. **Performance testing:**
```bash
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

4. **Review init script output:** All logging goes to serial console (stdio)

### Common Issues

See `docs/troubleshooting.md` for detailed troubleshooting, but quick fixes:

- **"No model disk found"**: Create with `./scripts/make-model-disk.sh`
- **"Ext2 file too big" (macOS)**: Add `--use-docker` flag
- **Out of memory**: Increase RAM_MB (32768+ for Phi-3.5)
- **Slow performance**: Use Phi-3.5 mini Q4_K_M, enable HVF acceleration
- **Boot hangs**: Check that `console=ttyAMA0` is in kernel cmdline

## CI/CD

### GitHub Actions Workflow

Located at `.github/workflows/ci.yml`:

```yaml
jobs:
  smoke-boot-aarch64:
    - Install dependencies (QEMU, build tools)
    - Build kernel + initramfs via Buildroot
    - Run smoke boot test
```

**Dependencies installed:**
- bc, bison, build-essential, cpio, flex, git
- libncurses5-dev, libssl-dev, python3, rsync
- unzip, wget, qemu-system-arm, ripgrep

### Running CI Locally

```bash
# Smoke boot (what CI runs)
./scripts/ci/smoke-boot.sh

# Performance test (extended CI)
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

## Environment Variables Reference

### Build Variables
- `ZOSIA_BUILDROOT_REF`: Buildroot version (default: 2024.11.1)
- `ZOSIA_LLAMA_CPP_REF`: llama.cpp commit hash
- `ZOSIA_JOBS`: Build parallelism (default: nproc)
- `ZOSIA_NO_DOCKER`: Disable Docker on macOS (default: 0)
- `ZOSIA_IN_DOCKER`: Internal flag for Docker builds
- `ZOSIA_MAKE_SILENT`: Silent make output (default: 0)

### Runtime Variables (run-qemu-aarch64.sh)
- `RAM_MB`: VM RAM in megabytes (default: 32768)
- `QEMU_ACCEL`: QEMU acceleration (default: hvf on macOS)
- `QEMU_CPU`: CPU model (default: host on Apple Silicon)
- `APPEND_EXTRA`: Additional kernel cmdline arguments

### Boot Variables (kernel cmdline)
- `zosia.ci=1`: CI mode (power off after boot)
- `zosia.diag=1`: Diagnostic mode
- `zosia.selftest=1`: Self-test mode
- `zosia.perf=1`: Performance test mode
- `zosia.perf.tokens=N`: Perf test token count
- `zosia.llama_threads=N`: Thread count
- `zosia.llama_batch_threads=N`: Batch thread count
- `zosia.llama_args=a,b,c`: Extra llama arguments

### Performance Test Variables
- `PERF_MIN_TOK_S`: Minimum tok/s threshold (default: 20)
- `PERF_PROFILE`: Performance profile (phi35_fast, none)
- `PERF_THREADS`: Override thread count
- `PERF_BATCH_THREADS`: Override batch thread count
- `PERF_LLAMA_ARGS`: Comma-separated llama args
- `PERF_RUNS`: Number of runs (default: 1)
- `PERF_TOKENS`: Token count per run (default: varies by profile)
- `PERF_TIMEOUT`: Timeout in seconds (default: 300)
- `PERF_MATRIX_FILE`: Path to perf matrix file
- `PERF_LOOP`: Continuous loop mode (0 or 1)
- `PERF_FAIL_FAST`: Stop on first failure (0 or 1)
- `PERF_RESULTS`: CSV output file path
- `PERF_LOG_DIR`: Log directory path

## Quick Reference

### Essential Commands

```bash
# Build everything
./scripts/build-buildroot.sh

# Create model disk (default)
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker

# Run VM
./scripts/run-qemu-aarch64.sh

# Smoke test
./scripts/ci/smoke-boot.sh

# Performance test
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh

# Diagnostics
RAM_MB=2048 APPEND_EXTRA='zosia.diag=1' ./scripts/run-qemu-aarch64.sh
```

### File Locations

- Kernel: `artifacts/aarch64/Image`
- Initramfs: `artifacts/aarch64/initramfs.cpio.gz`
- Model disk: `models/model.img` (generated)
- Init script: `initramfs/init`
- Stub REPL: `initramfs/bin/zosia-repl`
- Buildroot config: `buildroot/external/configs/zosia_aarch64_defconfig`

### Documentation

- User guide: `README.md`
- Quick start: `docs/quickstart.md`
- Architecture: `docs/architecture.md`
- Troubleshooting: `docs/troubleshooting.md`
- AI guidelines: `AGENTS.md`
- This guide: `CLAUDE.md`

## Version Information

- **Buildroot**: 2024.11.1 (pinned in `scripts/versions.sh`)
- **llama.cpp**: Commit 2995341730f18deb64faa4538bda113328fd791f
- **Default model**: Phi-3.5 mini instruct Q4_K_M
- **Target platform**: QEMU AArch64 on macOS (Apple Silicon)
- **OS**: Minimal Linux (kernel + BusyBox initramfs)

## Getting Help

- Review `docs/troubleshooting.md` for common issues
- Check `AGENTS.md` for project constraints and goals
- Examine `initramfs/init` to understand boot flow
- Look at existing scripts in `scripts/` for patterns
- Review `.agent/PLANS.md` for ExecPlan template

---

**Last Updated**: 2026-01-04
**Project Status**: MVP complete (v0.0.1 alpha)
