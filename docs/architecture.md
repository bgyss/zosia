# Architecture

## Boot flow

1) `qemu-system-aarch64` boots a Linux `Image` with an initramfs.
2) `/init` mounts `/proc`, `/sys`, `/dev`.
3) `/init` mounts the virtio block device at `/models`.
4) `/init` `exec`s `llama-run` with `/models/model.gguf` (or `llama-cli -m /models/model.gguf`) on the serial console.
5) When the LLM process exits (or on Ctrl+C), the VM powers off.

## Storage layout

- Initramfs: BusyBox + `/init` + `llama-run` (or `llama-cli`, or a stub in CI).
- Model disk: ext4 image with `/model.gguf` (mounted at `/models/model.gguf`).
