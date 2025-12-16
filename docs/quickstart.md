# Quickstart

## Prereqs (macOS)

- QEMU (`qemu-system-aarch64`)
- e2fsprogs (`mkfs.ext4`, `debugfs`)
- A Linux build environment for Buildroot (recommended: Docker)

Suggested installs:

```bash
brew install qemu e2fsprogs
```

If you use Nix, include equivalents of `qemu` and `e2fsprogs` (`mkfs.ext4`, `debugfs`) in your environment.

## Build

1) Build kernel + initramfs (Buildroot):

```bash
./scripts/build-buildroot.sh
```

2) Create a model disk image from a local GGUF (default):

```bash
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker
```

Tip: drop GGUF files into `models/` (ignored by git) for convenience.
The model disk filesystem reserves 0% for root to avoid “file too big” on large GGUFs.
On macOS, if you see “Ext2 file too big” for large models, rerun with `--use-docker` (requires Docker + network; first run pulls a Debian image).

We validated `gpt-oss-20b` (MXFP4) but it was too slow for interactive use on CPU in QEMU, so the docs default to Phi-3.5 mini for better tok/s.

## Run

```bash
./scripts/run-qemu-aarch64.sh
```

On Apple Silicon, the run script defaults to `QEMU_ACCEL=hvf` and `QEMU_CPU=host` for faster emulation.

Smoke boot (CI-style poweroff):

```bash
RAM_MB=2048 APPEND_EXTRA='zosia.ci=1' ./scripts/run-qemu-aarch64.sh
```

Perf test (requires model disk):

```bash
RAM_MB=32768 APPEND_EXTRA='zosia.perf=1' ./scripts/run-qemu-aarch64.sh
```

Perf test (scripted, prints tok/s and powers off). Defaults to the Phi-3.5 mini profile and `PERF_MIN_TOK_S=20` unless you override threads/args:

```bash
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

Recommended Phi-3.5 mini profile (sets 128 tokens):

```bash
PERF_PROFILE=phi35_fast PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

Continuous tuning loop:

```bash
./scripts/ci/gen-perf-matrix.sh
PERF_MATRIX_FILE=perf.matrix PERF_LOOP=1 PERF_FAIL_FAST=0 \
  PERF_RESULTS=/tmp/zosia-perf.csv PERF_LOG_DIR=/tmp/zosia-perf-logs \
  ./scripts/ci/perf-boot.sh
```

Shutdown: type `/poweroff` in the prompt, or press Ctrl+C.
