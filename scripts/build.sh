#!/usr/bin/env bash
# Build SUPER OS.
#
#   ./scripts/build.sh
#   ./scripts/build.sh user/demo.qu
#
# Set QUANT_DIR / QUANT_EXE / CLANG_DIR to override the defaults.
set -euo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$scripts_dir")"
build_dir="$root/build"

quant_dir="${QUANT_DIR:-$(dirname "$root")/quant}"
qu="${QUANT_EXE:-$quant_dir/build/bin/qu.exe}"
if [[ -n "${CLANG_DIR:-}" ]]; then
    clang="$CLANG_DIR/clang"
    ld_lld="$CLANG_DIR/ld.lld"
else
    clang="clang"
    ld_lld="ld.lld"
fi
clang="${CLANG:-$clang}"
ld_lld="${LD_LLD:-$ld_lld}"

need_tool() {
    if command -v "$1" >/dev/null 2>&1 || [[ -f "$1" ]]; then
        return 0
    fi
    echo "missing tool: $1" >&2
    exit 1
}

for tool in "$qu" "$clang" "$ld_lld"; do
    need_tool "$tool"
done

mkdir -p "$build_dir"

step() {
    local name="$1"
    shift
    echo "[*] $name"
    "$@"
}

programs=("$@")
if (( ${#programs[@]} == 0 )); then
    programs=("user/hello.qu" "user/demo.qu")
fi

user_elfs=()
for program in "${programs[@]}"; do
    source="$root/$program"
    name="$(basename "${program%.*}").elf"
    target="$build_dir/$name"
    step "compile user program  ($program)" "$qu" --target x86_64-superos "$source" -o "$target"
    user_elfs+=("$target")
done

step "compile Quant kernel" \
    "$qu" --target x86_64-superos -c -o "$build_dir/kmain.o" "$root/kernel/kmain.qu"

step "assemble boot64.s" \
    "$clang" --target=x86_64-unknown-elf -c "$root/kernel/boot64.s" -o "$build_dir/boot64.o"

step "assemble hw.s" \
    "$clang" --target=x86_64-unknown-elf -c "$root/kernel/hw.s" -o "$build_dir/hw.o"

step "link flat 64-bit kernel" \
    "$ld_lld" -T "$root/kernel/kernel64.ld" --oformat=binary \
        -o "$build_dir/kernel64.bin" \
        "$build_dir/boot64.o" "$build_dir/hw.o" "$build_dir/kmain.o"

step "assemble 32-bit Multiboot container" \
    "$clang" --target=i386-unknown-elf -c "$root/kernel/boot32.s" -o "$build_dir/boot32.o" -I "$build_dir"

step "link bootable Multiboot ELF" \
    "$ld_lld" -m elf_i386 -T "$root/kernel/boot32.ld" \
        -o "$build_dir/superos.elf" "$build_dir/boot32.o"

echo
echo "OK: $build_dir/superos.elf"
for elf in "${user_elfs[@]}"; do
    echo "    $elf"
done
