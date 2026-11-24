# Noeda developer workstation - step 1 (Windows): install WSL2 + Ubuntu. Nothing else.
# Everything else (Docker, Git, editors, pyenv) is installed inside Ubuntu by 02-setup-ubuntu.sh.
#
# Usage:  powershell -ExecutionPolicy Bypass -File .\01-install-wsl.ps1
# On a fresh machine run it twice: the first run installs WSL (then reboot), the second installs Ubuntu.
#
# Run from an ELEVATED PowerShell (Run as Administrator), NOT from inside another app's
# terminal (e.g. the Claude desktop app): sandboxed apps can redirect installs.

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'ERROR: Run this from an elevated PowerShell (Run as Administrator).' -ForegroundColor Red
    exit 1
}

$hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$vt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
if (-not $hv -and -not $vt) {
    Write-Host 'WARNING: CPU virtualization looks disabled. Enable Intel VT-x / AMD-V (SVM) in BIOS/UEFI.' -ForegroundColor Yellow
}

# WSL networking: mirrored mode instead of the default NAT. On the first test machine NAT
# downloads ran at ~31 KB/s vs 3+ MB/s on Windows, so apt looked hung. Only written if the
# user has no .wslconfig yet; an existing file is left alone (check it has networkingMode=mirrored).
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
if (-not (Test-Path $wslconfig)) {
    @"
# WSL2 settings for all distros (written by noeda-setup/01-install-wsl.ps1).
# Applies after:  wsl --shutdown
[wsl2]
# Share Windows' network stack instead of NAT (NAT can be ~100x slower for downloads).
networkingMode=mirrored
# Resolve DNS through Windows (works with VPNs and corporate DNS).
dnsTunneling=true
"@ | Set-Content -Path $wslconfig -Encoding ascii
    Write-Host "Wrote $wslconfig (mirrored networking)." -ForegroundColor Green
} elseif (-not (Select-String -Path $wslconfig -Pattern '^\s*networkingMode\s*=\s*mirrored' -Quiet)) {
    Write-Host "NOTE: $wslconfig exists without networkingMode=mirrored. If downloads in WSL are slow, add it under [wsl2]." -ForegroundColor Yellow
}

# Installs WSL and Ubuntu. Safe to re-run.
# On a machine without WSL, the first run only installs WSL + the Virtual Machine Platform
# feature and needs a reboot; Ubuntu is installed by running this script again after the reboot.
wsl --install -d Ubuntu

# wsl.exe prints UTF-16; strip NULs before comparing.
$distros = @(wsl --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })

# This folder as Ubuntu sees it (C:\Users\Jo\x -> /mnt/c/Users/Jo/x), quoted for bash.
$linuxPath = '/mnt/c/<path-to>/noeda-setup/02-setup-ubuntu.sh'
$setupScript = Join-Path $PSScriptRoot '02-setup-ubuntu.sh'
if ($setupScript -match '^([A-Za-z]):\\(.*)$') {
    $linuxPath = '/mnt/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
}
$linuxPath = "'" + ($linuxPath -replace "'", "'\''") + "'"

Write-Host ''
if ($distros -contains 'Ubuntu') {
    Write-Host 'Ubuntu is installed.' -ForegroundColor Green
    Write-Host 'Next:' -ForegroundColor Cyan
    Write-Host '  1. Open Ubuntu (Windows Terminal > the down-arrow menu > Ubuntu, or Win+R:  wsl ~).'
    Write-Host '     The first start asks you to create your Linux username and password.'
    Write-Host '     (Start-menu search may also show a Microsoft Store "Ubuntu" app - do not install that.)'
    Write-Host "  2. In Ubuntu, run:  bash $linuxPath 2>&1 | tee ~/setup-ubuntu.log"
} else {
    Write-Host 'WSL is installed but Ubuntu is not yet.' -ForegroundColor Yellow
    Write-Host 'Next: REBOOT, then run this script again to install Ubuntu.' -ForegroundColor Yellow
}
