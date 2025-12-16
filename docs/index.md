# zosia

Boot a minimal Linux VM directly into an interactive GPT-style prompt over the serial console.

This repo targets:

- Host: macOS (Apple Silicon)
- VM: `qemu-system-aarch64`
- Guest userspace: Buildroot + BusyBox + `llama.cpp` (`llama-cli`)
- Model: Phi-3.5 mini Q4_K_M GGUF on a dedicated ext4 “model disk” (gpt-oss-20b tested, but slower)

Start here: [Quickstart](quickstart.md).

## Getting started (minimal)

```bash
./scripts/build-buildroot.sh
./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker
./scripts/run-qemu-aarch64.sh
```

## Release checklist

- Build clean: `./scripts/build-buildroot.sh`
- Model disk: `./scripts/make-model-disk.sh models/Phi-3.5-mini-instruct-Q4_K_M.gguf --use-docker`
- Boot check: `./scripts/run-qemu-aarch64.sh`
- Perf check: `PERF_MIN_TOK_S=20 ./scripts/ci/perf-boot.sh`
- Docs sanity: `README.md` + `docs/quickstart.md` up to date

## Support matrix

- Host OS: macOS (Apple Silicon)
- QEMU: `qemu-system-aarch64` (version not pinned; recent releases recommended)

## Known limitations

- CPU-only inference; large models are slow under QEMU.
- High RAM requirements for 20B-class models.
- Serial console only; no GUI.
- Minimal userspace (no shell, no networking beyond what the model loader needs).
