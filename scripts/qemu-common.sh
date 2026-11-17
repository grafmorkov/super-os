#!/usr/bin/env bash
# Shared helpers for the SUPER OS QEMU launchers.
# Source this file from the other scripts in this directory.

# find_qemu - print the path to qemu-system-x86_64.
find_qemu() {
    if [[ -n "${QEMU_EXE:-}" ]]; then
        printf '%s\n' "$QEMU_EXE"
        return 0
    fi

    local cmd
    cmd=$(command -v qemu-system-x86_64 2>/dev/null || true)
    if [[ -n "$cmd" ]]; then
        printf '%s\n' "$cmd"
        return 0
    fi

    local candidate
    for candidate in \
        "/c/Program Files/qemu/qemu-system-x86_64.exe" \
        "/c/Program Files (x86)/qemu/qemu-system-x86_64.exe" \
        "/usr/bin/qemu-system-x86_64"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    echo "qemu-system-x86_64 not found; install QEMU or set QEMU_EXE" >&2
    return 1
}

# resolve_initrd <path> <root> - print an absolute path QEMU can open.
#
# QEMU's -initrd parser splits its argument at spaces on Windows, even when the
# path reaches it correctly quoted. Images living under a path with spaces are
# copied to a scratch directory first.
resolve_initrd() {
    local path="$1" root="$2"
    [[ -z "$path" ]] && return 0

    local resolved="$path"
    if [[ "$resolved" != /* && "$resolved" != [A-Za-z]:* ]]; then
        resolved="$root/$resolved"
    fi
    if [[ ! -e "$resolved" ]]; then
        echo "initrd not found: $resolved" >&2
        return 1
    fi

    # Normalise to an absolute path.
    resolved="$(cd "$(dirname "$resolved")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$resolved")")"

    if [[ "$resolved" == *" "* ]]; then
        local stage="${TMPDIR:-/tmp}/superos-initrd"
        mkdir -p "$stage"
        local staged="$stage/$(basename "$resolved")"
        cp -f "$resolved" "$staged"
        echo "(initrd staged at $staged)" >&2
        resolved="$staged"
    fi

    printf '%s\n' "$resolved"
}
