# Noeda developer workstation - remove the Windows-side tools of the OLD setup
# (the Chocolatey-based 01-install-tools.ps1 on the main branch), e.g. when moving a
# machine to the WSL-only setup:  .\02-uninstall-tools.ps1 --cursor --vscode --docker --git --gh
#
# Usage (from an ELEVATED PowerShell, unless --dry-run):
#   .\02-uninstall-tools.ps1 --all
#   .\02-uninstall-tools.ps1 --cursor --vscode
#   .\02-uninstall-tools.ps1 --docker --dry-run
#   .\02-uninstall-tools.ps1 --help
#
# Nothing is removed unless at least one component flag (or --all) is given.
# Windows PowerShell 5.1 compatible. Flags are case-insensitive.

$ErrorActionPreference = 'Continue'
$scriptName = Split-Path -Leaf $PSCommandPath

# Order matters for --all: editors first, Docker before Git, WSL last
# (Docker Desktop runs on WSL2).
$components = [ordered]@{
    cursor = 'Cursor (choco package cursoride)'
    vscode = 'Visual Studio Code (choco package vscode)'
    docker = 'Docker Desktop (choco package docker-desktop) and your docker-users group membership'
    git    = 'Git for Windows incl. Git Credential Manager (choco package git)'
    gh     = 'GitHub CLI for Windows (choco package gh)'
    wsl    = 'WSL2 itself, ALL installed distros and their files (e.g. Ubuntu, ~/work/noe), and the WSL / Virtual Machine Platform Windows features'
}

function Show-Usage {
    Write-Host @"
Usage: $scriptName <component flags> [--dry-run] [--yes]

Removes Windows tools installed by the old Chocolatey setup. Choose what to remove:

  --cursor    $($components.cursor)
  --vscode    $($components.vscode)
  --docker    $($components.docker)
  --git       $($components.git)
  --gh        $($components.gh)
  --wsl       $($components.wsl)
  --all       All of the above

Options:
  --dry-run   Show what would be removed; change nothing (no admin needed)
  --yes       Skip the confirmation prompt for --wsl
  --help      Show this help

Moving to the WSL-only setup: use --cursor --vscode --docker --git --gh (keep WSL).
Run from your own elevated PowerShell, not a terminal inside another app.
Run from an elevated PowerShell (Run as Administrator).
"@
}

function Fail-Usage([string]$message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    Write-Host ''
    Show-Usage
    exit 2
}

# ---------- Parse arguments ----------
$selected = New-Object System.Collections.Generic.List[string]
$dryRun = $false
$assumeYes = $false

if ($args.Count -eq 0) {
    Fail-Usage 'No components specified. Pass --all to remove everything, or name the components to remove.'
}

foreach ($raw in $args) {
    $arg = "$raw".ToLowerInvariant()
    switch -Regex ($arg) {
        '^--(help|h)$|^-h$|^/\?$' { Show-Usage; exit 0 }
        '^--all$'      { foreach ($k in $components.Keys) { if (-not $selected.Contains($k)) { $selected.Add($k) } } continue }
        '^--dry-run$'  { $dryRun = $true; continue }
        '^--yes$'      { $assumeYes = $true; continue }
        '^--(\w+)$'    {
            $name = $Matches[1]
            if ($components.Contains($name)) {
                if (-not $selected.Contains($name)) { $selected.Add($name) }
                continue
            }
            Fail-Usage "Unknown option '$raw'."
        }
        default        { Fail-Usage "Unknown option '$raw'." }
    }
}

if ($selected.Count -eq 0) {
    Fail-Usage 'No components specified. --dry-run and --yes need at least one component flag, or --all.'
}

# Run in the fixed order, whatever order the flags were given in.
$plan = @($components.Keys | Where-Object { $selected.Contains($_) })

# ---------- Pre-flight checks ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $dryRun -and -not $isAdmin) {
    Write-Host 'ERROR: Run this from an elevated PowerShell (Run as Administrator), or add --dry-run.' -ForegroundColor Red
    exit 1
}
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host 'ERROR: Chocolatey (choco) not found on PATH.' -ForegroundColor Red
    exit 1
}

$prefix = ''
if ($dryRun) { $prefix = '[dry-run] ' }

Write-Host "${prefix}Will remove:" -ForegroundColor Cyan
foreach ($k in $plan) { Write-Host "  - $($components[$k])" }
Write-Host ''

if ($plan -contains 'wsl' -and -not $dryRun -and -not $assumeYes) {
    Write-Host 'WARNING: --wsl deletes every WSL distro and everything inside it (including any code' -ForegroundColor Yellow
    Write-Host '         not pushed to GitHub). Docker Desktop will not work without WSL.' -ForegroundColor Yellow
    $answer = Read-Host "Type 'yes' to continue"
    if ($answer -ne 'yes') { Write-Host 'Aborted. Nothing was changed.'; exit 3 }
}

if (-not $dryRun) {
    Start-Transcript -Path (Join-Path $PSScriptRoot 'uninstall-log.txt') -Append | Out-Null
}

# ---------- Helpers ----------
function Test-ChocoInstalled([string]$package) {
    $line = choco list --exact $package --limit-output 2>$null
    return [bool]($line | Where-Object { $_ -like "$package|*" })
}

function Remove-ChocoPackage([string]$package) {
    if (-not (Test-ChocoInstalled $package)) {
        Write-Host "${prefix}$package is not installed through Chocolatey - skipping."
        return
    }
    if ($dryRun) {
        Write-Host "${prefix}choco uninstall $package -y --remove-dependencies"
        return
    }
    # --remove-dependencies also removes the *.install packages (git.install, vscode.install)
    choco uninstall $package -y --remove-dependencies
}

$script:rebootNeeded = $false

# ---------- Actions ----------
foreach ($k in $plan) {
    Write-Host "`n=== $k ===" -ForegroundColor Cyan
    switch ($k) {
        'cursor' { Remove-ChocoPackage 'cursoride' }
        'vscode' { Remove-ChocoPackage 'vscode' }
        'git'    { Remove-ChocoPackage 'git' }
        'gh'     { Remove-ChocoPackage 'gh' }
        'docker' {
            if ($dryRun) {
                Write-Host "${prefix}Stop Docker Desktop if running"
            } else {
                Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue | Stop-Process -Force
            }
            Remove-ChocoPackage 'docker-desktop'

            $user = "$env:USERDOMAIN\$env:USERNAME"
            $group = Get-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue
            if ($group) {
                $isMember = Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq $user }
                if ($isMember) {
                    if ($dryRun) { Write-Host "${prefix}Remove $user from docker-users" }
                    else { Remove-LocalGroupMember -Group 'docker-users' -Member $user -ErrorAction SilentlyContinue }
                }
                $remaining = @(Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne $user })
                if ($remaining.Count -eq 0) {
                    if ($dryRun) { Write-Host "${prefix}Delete the now-empty docker-users group" }
                    else { Remove-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue }
                }
            }
        }
        'wsl' {
            if ($dryRun) {
                Write-Host "${prefix}wsl --shutdown"
                Write-Host "${prefix}wsl --unregister <each distro>   (deletes its files)"
                Write-Host "${prefix}wsl --uninstall"
                Write-Host "${prefix}Disable Windows features: Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform"
            } else {
                wsl --shutdown
                # wsl.exe prints UTF-16; strip NULs so the names compare cleanly
                $distros = @(wsl --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } |
                    Where-Object { $_ })
                foreach ($d in $distros) {
                    Write-Host "Unregistering WSL distro: $d"
                    wsl --unregister $d
                }
                wsl --uninstall
                foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
                    $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
                    if ($state -and $state.State -eq 'Enabled') {
                        Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
                        Write-Host "Disabled Windows feature: $feature"
                    }
                }
            }
            $script:rebootNeeded = $true
        }
    }
}

if (-not $dryRun) { Stop-Transcript | Out-Null }

Write-Host ''
if ($dryRun) {
    Write-Host 'Dry run finished. Nothing was changed.' -ForegroundColor Green
} else {
    Write-Host 'Done.' -ForegroundColor Green
    if ($script:rebootNeeded) {
        Write-Host 'A REBOOT is required to finish removing WSL.' -ForegroundColor Yellow
    }
}
exit 0
