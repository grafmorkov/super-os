# Run SUPER OS interactively in QEMU.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Gui
#   powershell -ExecutionPolicy Bypass -File .\scripts\run.ps1 -Gui -Initrd build\demo.elf
#
# By default the terminal is attached to COM1 and no QEMU window is opened.
# With -Gui a QEMU window shows the VGA text console; the PS/2 keyboard is
# routed there while serial output still appears in this terminal.
# Use -Display sdl to pick a different QEMU display backend.

param(
    [string]$Initrd = "",
    [string]$Kernel = "build\superos.elf",
    [switch]$Gui,
    [string]$Display = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "qemu-common.ps1")

if ($env:SUPEROS_INITRD) { $Initrd = $env:SUPEROS_INITRD }

$kernelPath = $Kernel
if (-not [System.IO.Path]::IsPathRooted($kernelPath)) {
    $kernelPath = Join-Path $root $kernelPath
}
if (-not (Test-Path $kernelPath)) {
    throw "$kernelPath not found; run build.ps1 first"
}

$initrdPath = Resolve-Initrd $Initrd $root

if ($Display -ne "") {
    $displayMode = $Display
} elseif ($Gui) {
    $displayMode = "gtk"
} else {
    $displayMode = "none"
}

$qemuArgs = @(
    "-kernel", ([System.IO.Path]::GetFullPath($kernelPath)),
    "-display", $displayMode,
    "-serial", "stdio",
    "-monitor", "none",
    "-device", "isa-debug-exit,iobase=0x501,iosize=0x04",
    "-no-reboot"
)
if ($initrdPath -ne "") {
    $qemuArgs += @("-initrd", $initrdPath)
}

Write-Host "SUPER OS - Ctrl+C quits QEMU, 'poweroff' exits from the shell"
if ($Gui -or ($Display -ne "" -and $Display -ne "none")) {
    Write-Host "Click the QEMU window and type there (PS/2 keyboard)."
}
& (Get-QemuExe) @qemuArgs
