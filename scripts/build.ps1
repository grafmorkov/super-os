# Build SUPER OS.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1 -UserPrograms user\demo.qu
#
# Set QUANT_DIR / QUANT_EXE / CLANG_DIR to override the defaults.
param(
    [Alias("UserProgram")]
    [string[]]$UserPrograms = @("user\hello.qu", "user\demo.qu")
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"

$quantDir = if ($env:QUANT_DIR) { $env:QUANT_DIR } else { "C:\Users\Zero\repo\quant" }
$qu = if ($env:QUANT_EXE) { $env:QUANT_EXE } else { Join-Path $quantDir "build\bin\qu.exe" }
$clangDir = if ($env:CLANG_DIR) { $env:CLANG_DIR } else { "C:\tools\clang\bin" }
$clang = Join-Path $clangDir "clang.exe"
$ld = Join-Path $clangDir "ld.lld.exe"

foreach ($tool in @($qu, $clang, $ld)) {
    if (-not (Test-Path $tool)) { throw "missing tool: $tool" }
}

New-Item -ItemType Directory -Force -Path $build | Out-Null

function Step([string]$name, [scriptblock]$body) {
    Write-Host "[*] $name"
    & $body
    if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
}

$userElfs = @()

foreach ($program in $UserPrograms) {
    $source = Join-Path $root $program
    $name = [System.IO.Path]::GetFileNameWithoutExtension($program) + ".elf"
    $target = Join-Path $build $name
    Step "compile user program  ($program)" {
        & $qu --target x86_64-superos $source -o $target
    }
    $userElfs += $target
}

Step "compile Quant kernel" {
    & $qu --target x86_64-superos -c -o (Join-Path $build "kmain.o") (Join-Path $root "kernel\kmain.qu")
}

Step "assemble boot64.s" {
    & $clang --target=x86_64-unknown-elf -c (Join-Path $root "kernel\boot64.s") -o (Join-Path $build "boot64.o")
}

Step "assemble hw.s" {
    & $clang --target=x86_64-unknown-elf -c (Join-Path $root "kernel\hw.s") -o (Join-Path $build "hw.o")
}

Step "link flat 64-bit kernel" {
    & $ld -T (Join-Path $root "kernel\kernel64.ld") --oformat=binary `
        -o (Join-Path $build "kernel64.bin") `
        (Join-Path $build "boot64.o") (Join-Path $build "hw.o") (Join-Path $build "kmain.o")
}

Step "assemble 32-bit Multiboot container" {
    & $clang --target=i386-unknown-elf -c (Join-Path $root "kernel\boot32.s") -o (Join-Path $build "boot32.o") -I $build
}

Step "link bootable Multiboot ELF" {
    & $ld -m elf_i386 -T (Join-Path $root "kernel\boot32.ld") -o (Join-Path $build "superos.elf") (Join-Path $build "boot32.o")
}

Write-Host ""
Write-Host "OK: $build\superos.elf"
foreach ($elf in $userElfs) {
    Write-Host "    $elf"
}
