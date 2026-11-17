param(
    [string]$Initrd = "",
    [string]$CommandList = "help;poweroff",
    [int]$BootWaitMs = 2000,
    [int]$CharDelayMs = 3
)

# `powershell -File` loses spaces inside string parameters, so the initrd can
# also be supplied through SUPEROS_INITRD.
if ($env:SUPEROS_INITRD) { $Initrd = $env:SUPEROS_INITRD }

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "qemu-common.ps1")

$kernel = Join-Path $root "build\superos.elf"
if (-not (Test-Path $kernel)) {
    throw "build\superos.elf not found; run build.ps1 first"
}

$initrdPath = Resolve-Initrd $Initrd $root
$Commands = $CommandList -split ';' | Where-Object { $_ -ne "" }

$qemuArgs = @(
    "-kernel", $kernel,
    "-display", "none",
    "-serial", "stdio",
    "-monitor", "none",
    "-device", "isa-debug-exit,iobase=0x501,iosize=0x04",
    "-no-reboot"
)
if ($initrdPath -ne "") {
    $qemuArgs += @("-initrd", $initrdPath)
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Get-QemuExe
$psi.Arguments = ($qemuArgs | ForEach-Object { if ($_ -match ' ') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
Start-Sleep -Milliseconds $BootWaitMs

foreach ($cmd in $Commands) {
    if ($proc.HasExited) { break }
    # QEMU's stdio chardev discards anything beyond the UART buffer in one
    # read, so feed the line at a typing-like pace.
    foreach ($ch in $cmd.ToCharArray()) {
        $proc.StandardInput.Write($ch)
        $proc.StandardInput.Flush()
        if ($CharDelayMs -gt 0) { Start-Sleep -Milliseconds $CharDelayMs }
    }
    $proc.StandardInput.Write("`n")
    $proc.StandardInput.Flush()
    Start-Sleep -Milliseconds 500
}

if (-not $proc.HasExited) {
    try { $proc.StandardInput.Close() } catch {}
}
if (-not $proc.WaitForExit(4000)) {
    try { $proc.Kill() } catch {}
    $proc.WaitForExit(2000) | Out-Null
}

$out = $proc.StandardOutput.ReadToEnd()
$err = $proc.StandardError.ReadToEnd()
Write-Output "=== qemu exit: $($proc.ExitCode) ==="
Write-Output $out
if ($err -ne "") { Write-Output "=== stderr ==="; Write-Output $err }
