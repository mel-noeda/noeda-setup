# Noeda developer workstation - step 1: install base tooling
# Run from an ELEVATED PowerShell (Run as Administrator).
# Prerequisite: Chocolatey installed (https://chocolatey.org/install).

$ErrorActionPreference = 'Continue'
$log = Join-Path $PSScriptRoot 'install-log.txt'
Start-Transcript -Path $log -Append

# 1. WSL2 (required by Docker Desktop). --no-distribution: Docker brings its own.
wsl --install --no-distribution

# 2. Tools via Chocolatey
choco install git -y --params "/GitAndUnixToolsOnPath /NoShellIntegration"
choco install vscode -y
choco install cursoride -y
choco install docker-desktop -y

# 3. Let the current user talk to Docker without elevation
$user = "$env:USERDOMAIN\$env:USERNAME"
if (-not (Get-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name 'docker-users' | Out-Null
}
Add-LocalGroupMember -Group 'docker-users' -Member $user -ErrorAction SilentlyContinue

Stop-Transcript
Write-Host "`nDone. A REBOOT is required to finish enabling WSL2 / Docker." -ForegroundColor Yellow
