# UEFI firmware (aarch64)

`scripts/run-qemu-aarch64.sh` can optionally use UEFI firmware if you set `ZOSIA_USE_UEFI=1`.

On macOS with Homebrew QEMU, the firmware is typically available at:

- `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`

If you prefer keeping a copy in-repo, place it here as:

- `assets/uefi/edk2-aarch64-code.fd`

