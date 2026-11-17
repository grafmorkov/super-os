# Shared helpers for the SUPER OS QEMU launchers.

# Get-QemuExe - locate qemu-system-x86_64.exe.
function Get-QemuExe {
    if ($env:QEMU_EXE) { return $env:QEMU_EXE }

    $cmd = Get-Command "qemu-system-x86_64.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\Program Files\qemu\qemu-system-x86_64.exe",
        "C:\Program Files (x86)\qemu\qemu-system-x86_64.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    throw "qemu-system-x86_64.exe not found; install QEMU or set QEMU_EXE"
}

# Resolve-Initrd - return an absolute path QEMU can open.
#
# QEMU's -initrd parser splits its argument at spaces on Windows, even when the
# path reaches it correctly quoted. Images living under a path with spaces are
# copied to a scratch directory first.
function Resolve-Initrd([string]$Path, [string]$Root) {
    if (-not $Path) { return "" }

    $resolved = $Path
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path $Root $resolved
    }
    if (-not (Test-Path $resolved)) { throw "initrd not found: $resolved" }
    $resolved = [System.IO.Path]::GetFullPath($resolved)

    if ($resolved -match ' ') {
        $stage = Join-Path $env:TEMP "superos-initrd"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $staged = Join-Path $stage ([System.IO.Path]::GetFileName($resolved))
        Copy-Item $resolved $staged -Force
        Write-Host "(initrd staged at $staged)"
        return $staged
    }

    return $resolved
}
