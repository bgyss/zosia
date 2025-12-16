# zosia

Boot a minimal Linux VM directly into an interactive GPT-style prompt over the serial console.

MVP status: boots into a serial-console prompt from initramfs; if a GGUF model disk is attached, it launches `llama-cli` automatically.

## Prereqs (macOS)

- QEMU (`qemu-system-aarch64`)
- e2fsprogs (`mkfs.ext4`, `debugfs`)
- A Linux build environment for Buildroot (recommended: Docker)

Suggested installs:

```bash
brew install qemu e2fsprogs
```

If you use Nix, you’ll want equivalents of `qemu-system-aarch64` and `mkfs.ext4`/`debugfs` (from `e2fsprogs`) available in your environment.

## Build (kernel + initramfs)

```bash
./scripts/build-buildroot.sh
```

Artifacts land in `artifacts/aarch64/`:

- `artifacts/aarch64/Image`
- `artifacts/aarch64/initramfs.cpio.gz`

## Model disk

Create a raw ext4 image containing `/model.gguf` (mounted at `/models` in the guest):

```bash
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker
```

Drop GGUF files into `models/` (ignored by git) for convenience.
The model disk filesystem reserves 0% for root to avoid “file too big” on large GGUFs.
On macOS, if you see “Ext2 file too big” for large models, use `--use-docker` (requires Docker + network; first run pulls a Debian image).

## Run (QEMU aarch64)

```bash
./scripts/run-qemu-aarch64.sh
```

On Apple Silicon, the run script defaults to `QEMU_ACCEL=hvf` and `QEMU_CPU=host` for faster emulation.
You can override with `QEMU_ACCEL=tcg` or `QEMU_CPU=max` if needed.

## What to run next

On your machine (so a Buildroot rebuild picks up changes):

- Rebuild kernel+initramfs (via Docker): `./scripts/build-buildroot.sh`
- Create the model disk (needs `e2fsprogs`): `./scripts/make-model-disk.sh models/your-model.gguf` (for large GGUFs on macOS, add `--use-docker`)
- Quick checks:
  - Llama binary present: `RAM_MB=2048 APPEND_EXTRA='zosia.selftest=1' ./scripts/run-qemu-aarch64.sh`
  - Disk/model detection: `RAM_MB=2048 APPEND_EXTRA='zosia.diag=1' ./scripts/run-qemu-aarch64.sh`
  - Perf smoke (needs model disk): `PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh`
  - Iterative perf (continuous): create a matrix file with lines like `8|8|-b,256,-c,2048`, then run `PERF_MATRIX_FILE=perf.matrix PERF_LOOP=1 PERF_FAIL_FAST=0 PERF_RESULTS=/tmp/zosia-perf.csv ./scripts/ci/perf-boot.sh`
  - Auto matrix helper: `./scripts/ci/gen-perf-matrix.sh` (writes `perf.matrix`)
- Interactive run: `RAM_MB=2048 ./scripts/run-qemu-aarch64.sh` (stub if no model; real inference needs much more RAM)

## Boot flags

Useful boot flags (passed via `APPEND_EXTRA`):

- `APPEND_EXTRA='zosia.ci=1'` (boot then power off)
- `APPEND_EXTRA='zosia.diag=1'` (print disk/binary/model detection then power off)
- `APPEND_EXTRA='zosia.selftest=1'` (run `llama-run --help` then power off)
- `APPEND_EXTRA='zosia.perf=1'` (run a short generation, print tok/s, then power off)
- `APPEND_EXTRA='zosia.perf=1 zosia.perf.tokens=128'` (perf test with custom token count)
- `APPEND_EXTRA='zosia.llama_threads=4 zosia.llama_batch_threads=4'` (override llama.cpp thread counts)
- `APPEND_EXTRA='zosia.llama_args=-c,2048'` (extra llama args, comma-separated)

## RAM guidance

- `RAM_MB=2048` is fine for smoke boot + stub prompt.
- Default run uses `RAM_MB=32768`. For `gpt-oss-20b`, plan on “tens of GB” (a practical starting point is `RAM_MB=32768` for a ~4-bit quant; go higher if you OOM).

## Model choice

We tested `gpt-oss-20b` (including MXFP4 quants) and it worked, but it was too slow for interactive use on CPU in QEMU. We settled on Phi-3.5 mini (Q4_K_M) as the default because it consistently hits the ~20 tok/s target with the current perf profile.

## Performance testing

Single perf run (prints tok/s and powers off). Defaults to the Phi-3.5 mini profile unless you override threads/args:

```bash
PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

Recommended profile for Phi-3.5 mini Q4_K_M (sets 128 tokens for steadier tok/s):

```bash
PERF_PROFILE=phi35_fast PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh
```

Continuous tuning loop (iterates a matrix of thread/args combos):

```bash
./scripts/ci/gen-perf-matrix.sh
PERF_MATRIX_FILE=perf.matrix PERF_LOOP=1 PERF_FAIL_FAST=0 \
  PERF_RESULTS=/tmp/zosia-perf.csv PERF_LOG_DIR=/tmp/zosia-perf-logs \
  ./scripts/ci/perf-boot.sh
```

Tuning overrides:

- `PERF_THREADS` / `PERF_BATCH_THREADS`
- `PERF_LLAMA_ARGS` (comma-separated)
- `PERF_RUNS`, `PERF_TOKENS`, `PERF_TIMEOUT`
- `PERF_PROFILE=phi35_fast` (SMP=6, threads=6, tokens=128, args `-b,256,-c,1024`)
- `PERF_PROFILE=none` (disable the default profile)

## Performance tips

- Use a smaller, instruction-tuned GGUF (e.g. 7B/8B class with 4-bit quant) if you need ~20 tok/s on CPU.
- Ensure QEMU acceleration is enabled (`QEMU_ACCEL=hvf` on macOS).
- Tune threads via `zosia.llama_threads` / `zosia.llama_batch_threads`.

Shutdown:

- Type `/poweroff` in the prompt, or
- Press Ctrl+C

## Docs

- `mkdocs.yml` + `docs/` (see `docs/quickstart.md`)
