#!/usr/bin/env bash
# Run SUPER OS interactively in QEMU.
#
#   ./scripts/run.sh
#   ./scripts/run.sh -Gui
#   ./scripts/run.sh -Gui -Initrd build/demo.elf
#
# By default the terminal is attached to COM1 and no QEMU window is opened.
# With -Gui a QEMU window shows the VGA text console; the PS/2 keyboard is
# routed there while serial output still appears in this terminal.
# Use -Display sdl to pick a different QEMU display backend.
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$scripts_dir")"
# shellcheck source=qemu-common.sh
source "$scripts_dir/qemu-common.sh"

initrd="${SUPEROS_INITRD:-}"
kernel="build/superos.elf"
gui=0
display=""

usage() {
    echo "usage: $0 [-Initrd FILE] [-Kernel FILE] [-Gui] [-Display BACKEND]" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        -Initrd|--initrd)   [[ $# -ge 2 ]] || usage; initrd="$2"; shift 2 ;;
        -Kernel|--kernel)   [[ $# -ge 2 ]] || usage; kernel="$2"; shift 2 ;;
        -Gui|--gui)         gui=1; shift ;;
        -Display|--display) [[ $# -ge 2 ]] || usage; display="$2"; shift 2 ;;
        -h|--help)          usage ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done

case "$kernel" in
    /*|[A-Za-z]:*) kernel_path="$kernel" ;;
    *)             kernel_path="$root/$kernel" ;;
esac
if [[ ! -f "$kernel_path" ]]; then
    echo "$kernel_path not found; run build.sh first" >&2
    exit 1
fi
kernel_path="$(cd "$(dirname "$kernel_path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$kernel_path")")"

initrd_path="$(resolve_initrd "$initrd" "$root")"

if [[ -n "$display" ]]; then
    display_mode="$display"
elif (( gui )); then
    display_mode="gtk"
else
    display_mode="none"
fi

qemu_args=(
    -kernel "$kernel_path"
    -display "$display_mode"
    -serial stdio
    -monitor none
    -device isa-debug-exit,iobase=0x501,iosize=0x04
    -no-reboot
)
if [[ -n "$initrd_path" ]]; then
    qemu_args+=(-initrd "$initrd_path")
fi

echo "SUPER OS - Ctrl+C quits QEMU, 'poweroff' exits from the shell"
if (( gui )) || [[ -n "$display" && "$display" != "none" ]]; then
    echo "Click the QEMU window and type there (PS/2 keyboard)."
fi

qemu="$(find_qemu)"
exec "$qemu" "${qemu_args[@]}"
