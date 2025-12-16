# Troubleshooting

## VM boots but no prompt

- Ensure the kernel cmdline includes `console=ttyAMA0`.
- Ensure QEMU runs with `-nographic` and `-serial stdio`.

## “No model disk found” / “missing /models/model.gguf”

- Create a model disk: `./scripts/make-model-disk.sh /path/to/model.gguf`
- Tip: drop GGUF files into `models/` (ignored by git) and use `./scripts/make-model-disk.sh models/your-model.gguf`.
- Ensure `./scripts/run-qemu-aarch64.sh` points at the right disk path.
- The model disk filesystem reserves 0% for root to avoid “file too big” on large GGUFs.

## “Ext2 file too big” while creating the model disk (macOS)

- Rerun with Docker: `./scripts/make-model-disk.sh models/your-model.gguf --use-docker` (requires Docker + network).

## Out of memory / slow startup

- Increase RAM in `./scripts/run-qemu-aarch64.sh` (20B models need a lot).
- Prefer `mmap`-friendly storage (local SSD).
- On macOS, ensure QEMU acceleration is enabled (`QEMU_ACCEL=hvf`).
- For better tok/s on CPU, use a smaller instruction-tuned GGUF and stronger quantization (Phi-3.5 mini Q4_K_M is the default profile).

## Perf test not producing output

- Use the scripted perf test to capture output: `./scripts/ci/perf-boot.sh` (defaults to `PERF_MIN_TOK_S=20`)
- If you need continuous tuning, generate a matrix and loop:
  - `./scripts/ci/gen-perf-matrix.sh`
  - `PERF_MATRIX_FILE=perf.matrix PERF_LOOP=1 PERF_FAIL_FAST=0 ./scripts/ci/perf-boot.sh`
- For Phi-3.5 mini, try the preset: `PERF_PROFILE=phi35_fast ./scripts/ci/perf-boot.sh`
- To disable the default profile, run: `PERF_PROFILE=none ./scripts/ci/perf-boot.sh`
