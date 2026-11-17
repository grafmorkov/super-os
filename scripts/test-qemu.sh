#!/usr/bin/env bash
# Automated headless boot test for SUPER OS.
#
#   ./scripts/test-qemu.sh
#   ./scripts/test-qemu.sh -CommandList "help;ticks;mem;poweroff"
#   ./scripts/test-qemu.sh -Initrd build/hello.elf
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$scripts_dir")"
# shellcheck source=qemu-common.sh
source "$scripts_dir/qemu-common.sh"

initrd="${SUPEROS_INITRD:-}"
command_list="help;poweroff"
boot_wait_ms=2000
char_delay_ms=3

usage() {
    echo "usage: $0 [-Initrd FILE] [-CommandList LIST] [-BootWaitMs N] [-CharDelayMs N]" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        -Initrd|--initrd)         [[ $# -ge 2 ]] || usage; initrd="$2"; shift 2 ;;
        -CommandList|--commands)  [[ $# -ge 2 ]] || usage; command_list="$2"; shift 2 ;;
        -BootWaitMs|--boot-wait)  [[ $# -ge 2 ]] || usage; boot_wait_ms="$2"; shift 2 ;;
        -CharDelayMs|--char-delay)[[ $# -ge 2 ]] || usage; char_delay_ms="$2"; shift 2 ;;
        -h|--help)                usage ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done

kernel="$root/build/superos.elf"
if [[ ! -f "$kernel" ]]; then
    echo "build/superos.elf not found; run build.sh first" >&2
    exit 1
fi

initrd_path="$(resolve_initrd "$initrd" "$root")"

qemu_args=(
    -kernel "$kernel"
    -display none
    -serial stdio
    -monitor none
    -device isa-debug-exit,iobase=0x501,iosize=0x04
    -no-reboot
)
if [[ -n "$initrd_path" ]]; then
    qemu_args+=(-initrd "$initrd_path")
fi

# Feed the guest through a FIFO so commands can be typed character by character.
fifo="$(mktemp -u "${TMPDIR:-/tmp}/superos-qemu.XXXXXX")"
out="$(mktemp "${TMPDIR:-/tmp}/superos-out.XXXXXX")"
err="$(mktemp "${TMPDIR:-/tmp}/superos-err.XXXXXX")"
mkfifo "$fifo"
trap 'rm -f "$fifo" "$out" "$err"' EXIT

ms_to_s() { printf '%d.%03d' "$(( $1 / 1000 ))" "$(( $1 % 1000 ))"; }

qemu="$(find_qemu)"
"$qemu" "${qemu_args[@]}" <"$fifo" >"$out" 2>"$err" &
qemu_pid=$!

exec 3>"$fifo"
sleep "$(ms_to_s "$boot_wait_ms")"

IFS=';' read -ra commands <<<"$command_list"
for cmd in "${commands[@]}"; do
    [[ -n "$cmd" ]] || continue
    kill -0 "$qemu_pid" 2>/dev/null || break
    # QEMU's stdio chardev discards anything beyond the UART buffer in one
    # read, so feed the line at a typing-like pace.
    for (( i = 0; i < ${#cmd}; i++ )); do
        printf '%s' "${cmd:i:1}" >&3 || break
        if (( char_delay_ms > 0 )); then
            sleep "$(ms_to_s "$char_delay_ms")"
        fi
    done
    printf '\n' >&3 || break
    sleep 0.5
done
exec 3>&-

# Give QEMU up to 4 seconds to exit on its own, then terminate it.
for (( i = 0; i < 40; i++ )); do
    kill -0 "$qemu_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    for (( i = 0; i < 20; i++ )); do
        kill -0 "$qemu_pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -9 "$qemu_pid" 2>/dev/null || true
fi

set +e
wait "$qemu_pid"
status=$?
set -e

echo "=== qemu exit: $status ==="
cat "$out"
if [[ -s "$err" ]]; then
    echo "=== stderr ==="
    cat "$err"
fi
