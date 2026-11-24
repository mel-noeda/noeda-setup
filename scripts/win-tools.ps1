# Noeda developer workstation - manage the Windows-side developer tools.
#
# Shows which tools are installed, then installs or removes the ones you pick. Handy when a
# machine was set up the old way (Docker Desktop, Git for Windows ...) and you want to move to
# the WSL-only setup, or when you want a Windows tool back.
#
# Usage (from an ELEVATED PowerShell; --list and --dry-run work without admin):
#   powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1                  # table, then asks what to do
#   powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --list           # table only
#   powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --gh --install
#   powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --docker --git --uninstall
#   powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --all --uninstall --dry-run
#
# Tools are installed with winget (ships with Windows 11), or Chocolatey if winget is missing.
# Tools are removed with whichever of the two installed them.
# Windows PowerShell 5.1 compatible. Flags are case-insensitive.

$ErrorActionPreference = 'Continue'
$scriptName = Split-Path -Leaf $PSCommandPath
$repoRoot = Split-Path -Parent $PSScriptRoot

# Uninstall order: editors first, Docker before Git, WSL last (Docker Desktop runs on WSL2).
# Install order is the reverse.
$tools = [ordered]@{
    cursor = @{ Title = 'Cursor';          Winget = 'Anysphere.Cursor';           Choco = 'cursoride';      Command = 'cursor' }
    vscode = @{ Title = 'VS Code';         Winget = 'Microsoft.VisualStudioCode'; Choco = 'vscode';         Command = 'code' }
    docker = @{ Title = 'Docker Desktop';  Winget = 'Docker.DockerDesktop';       Choco = 'docker-desktop'; Command = 'docker' }
    git    = @{ Title = 'Git for Windows'; Winget = 'Git.Git';                    Choco = 'git';            Command = 'git' }
    gh     = @{ Title = 'GitHub CLI';      Winget = 'GitHub.cli';                 Choco = 'gh';             Command = 'gh' }
    wsl    = @{ Title = 'WSL2';            Winget = $null;                        Choco = $null;            Command = 'wsl' }
}

function Show-Usage {
    Write-Host @"
Usage: $scriptName [tools] [--install | --uninstall] [--dry-run] [--yes]

Shows which Windows developer tools are installed, then installs or removes the ones you choose.
With no action given, it asks what to do.

Tools:
  --cursor   --vscode   --docker   --git   --gh   --wsl   --all

Actions:
  --install     Install the chosen tools (winget, or Chocolatey if winget is missing)
  --uninstall   Remove the chosen tools
  --list        Only show the table

Options:
  --dry-run     Show what would happen; change nothing (no admin needed)
  --yes         Skip the confirmation questions
  --help        Show this help

Notes:
  * Installing and removing needs an elevated PowerShell (Run as Administrator).
  * --wsl --uninstall deletes WSL and every distro in it, including files such as ~/work/noe.
  * --wsl --install runs 01-install-wsl.ps1 from the repo root.
  * Docker Desktop is NOT needed for the Noeda setup: Docker runs inside Ubuntu. Installing it
    here can clash with that (see docs/NOTES.md).
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
$action = ''
$listOnly = $false
$dryRun = $false
$assumeYes = $false

foreach ($raw in $args) {
    $arg = "$raw".ToLowerInvariant()
    switch -Regex ($arg) {
        '^--(help|h)$|^-h$|^/\?$' { Show-Usage; exit 0 }
        '^--all$'       { foreach ($k in $tools.Keys) { if (-not $selected.Contains($k)) { $selected.Add($k) } }; continue }
        '^--list$'      { $listOnly = $true; continue }
        '^--dry-run$'   { $dryRun = $true; continue }
        '^--yes$'       { $assumeYes = $true; continue }
        '^--(install|uninstall)$' {
            if ($action -and $action -ne $Matches[1]) { Fail-Usage 'Give either --install or --uninstall, not both.' }
            $action = $Matches[1]; continue
        }
        '^--(\w+)$'     {
            $name = $Matches[1]
            if ($tools.Contains($name)) { if (-not $selected.Contains($name)) { $selected.Add($name) }; continue }
            Fail-Usage "Unknown option '$raw'."
        }
        default         { Fail-Usage "Unknown option '$raw'." }
    }
}

# ---------- Helpers ----------
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$hasChoco = [bool](Get-Command choco -ErrorAction SilentlyContinue)

function Get-WslDistros {
    # wsl.exe prints UTF-16; strip NULs so the names compare cleanly.
    @(wsl --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

# For every tool: is it installed, and which package manager owns it?
function Get-ToolStatus {
    $chocoPackages = @{}
    if ($hasChoco) {
        foreach ($line in (choco list --local-only --limit-output 2>$null)) {
            $parts = "$line".Split('|')
            if ($parts.Count -ge 2) { $chocoPackages[$parts[0]] = $parts[1] }
        }
    }
    $result = [ordered]@{}
    foreach ($k in $tools.Keys) {
        $t = $tools[$k]
        $status = @{ Installed = $false; Via = ''; Detail = '' }
        if ($k -eq 'wsl') {
            wsl --version 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $status.Installed = $true
                $status.Via = 'Windows'
                $distros = Get-WslDistros
                if ($distros.Count -gt 0) { $status.Detail = 'distros: ' + ($distros -join ', ') }
            }
        } elseif ($t.Choco -and $chocoPackages.ContainsKey($t.Choco)) {
            $status.Installed = $true; $status.Via = 'Chocolatey'; $status.Detail = $chocoPackages[$t.Choco]
        } else {
            $viaWinget = $false
            if ($hasWinget) {
                winget list --id $t.Winget --exact --accept-source-agreements 2>$null | Out-Null
                $viaWinget = ($LASTEXITCODE -eq 0)
            }
            if ($viaWinget) {
                $status.Installed = $true; $status.Via = 'winget'
            } elseif (Get-Command $t.Command -ErrorAction SilentlyContinue) {
                $status.Installed = $true; $status.Via = 'other'
            }
        }
        $result[$k] = $status
    }
    $result
}

function Show-Table($status) {
    Write-Host ''
    Write-Host 'Windows developer tools on this machine:' -ForegroundColor Cyan
    Write-Host ('  {0,-2} {1,-16} {2,-14} {3,-11} {4}' -f '#', 'Tool', 'Installed', 'Via', 'Detail')
    Write-Host ('  {0,-2} {1,-16} {2,-14} {3,-11} {4}' -f '-', '----', '---------', '---', '------')
    $i = 0
    foreach ($k in $tools.Keys) {
        $i++
        $s = $status[$k]
        $label = 'no'; $color = 'DarkGray'
        if ($s.Installed) { $label = 'yes'; $color = 'Green' }
        Write-Host ('  {0,-2} {1,-16} ' -f $i, $tools[$k].Title) -NoNewline
        Write-Host ('{0,-14}' -f $label) -NoNewline -ForegroundColor $color
        Write-Host (' {0,-11} {1}' -f $s.Via, $s.Detail)
    }
    if ($hasWinget -or $hasChoco) {
        $mgr = @(); if ($hasWinget) { $mgr += 'winget' }; if ($hasChoco) { $mgr += 'Chocolatey' }
        Write-Host ''
        Write-Host ('  Package managers found: ' + ($mgr -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host '  No package manager found (winget or Chocolatey): tools cannot be installed or removed here.' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Read-Answer([string]$prompt) {
    try { return (Read-Host $prompt).Trim() } catch { Write-Host 'ERROR: this needs an interactive terminal; pass flags instead (see --help).' -ForegroundColor Red; exit 2 }
}

# ---------- Show the table ----------
$status = Get-ToolStatus
Show-Table $status
if ($listOnly) { exit 0 }

# ---------- Ask for whatever the flags did not say ----------
$interactive = (-not $action) -or ($selected.Count -eq 0)
if (-not $action) {
    $answer = (Read-Answer 'What do you want to do? [i]nstall, [u]ninstall, [q]uit').ToLowerInvariant()
    switch -Regex ($answer) {
        '^i'    { $action = 'install' }
        '^u'    { $action = 'uninstall' }
        default { Write-Host 'Nothing changed.'; exit 0 }
    }
}
if ($selected.Count -eq 0) {
    $keys = @($tools.Keys)
    $answer = Read-Answer "Which tools to $action? Numbers or names separated by commas (for example 2,gh), 'all', or Enter to cancel"
    if (-not $answer) { Write-Host 'Nothing changed.'; exit 0 }
    foreach ($item in ($answer -split '[,\s]+' | Where-Object { $_ })) {
        $item = $item.ToLowerInvariant().TrimStart('-')
        if ($item -eq 'all') { foreach ($k in $keys) { if (-not $selected.Contains($k)) { $selected.Add($k) } }; continue }
        $n = 0
        if ([int]::TryParse($item, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) { $item = $keys[$n - 1] }
        if ($tools.Contains($item)) { if (-not $selected.Contains($item)) { $selected.Add($item) } }
        else { Write-Host "ERROR: don't know '$item'." -ForegroundColor Red; exit 2 }
    }
}

# Fixed order, whatever order the flags were given in: uninstall top to bottom, install bottom to top.
$plan = @($tools.Keys | Where-Object { $selected.Contains($_) })
if ($action -eq 'install') { [array]::Reverse($plan) }

# ---------- Pre-flight ----------
if (-not $dryRun -and -not (Test-Admin)) {
    Write-Host 'ERROR: Run this from an elevated PowerShell (Run as Administrator), or add --dry-run.' -ForegroundColor Red
    exit 1
}
$needsManager = @($plan | Where-Object { $_ -ne 'wsl' })
if ($needsManager.Count -gt 0 -and -not $hasWinget -and -not $hasChoco) {
    Write-Host 'ERROR: neither winget nor Chocolatey was found. winget ships with Windows 11 ("App Installer" in the Microsoft Store).' -ForegroundColor Red
    exit 1
}

$prefix = ''
if ($dryRun) { $prefix = '[dry-run] ' }
Write-Host "${prefix}Will ${action}:" -ForegroundColor Cyan
foreach ($k in $plan) { Write-Host ('  - {0}' -f $tools[$k].Title) }
Write-Host ''

if ($action -eq 'install' -and $plan -contains 'docker') {
    Write-Host 'NOTE: Docker Desktop is not needed for the Noeda setup (Docker runs inside Ubuntu), and it can' -ForegroundColor Yellow
    Write-Host '      take over the docker command there. See docs/NOTES.md before installing it.' -ForegroundColor Yellow
    Write-Host ''
}
if ($action -eq 'uninstall' -and $plan -contains 'wsl' -and -not $dryRun -and -not $assumeYes) {
    Write-Host 'WARNING: removing WSL deletes every WSL distro and everything inside it (including any code' -ForegroundColor Yellow
    Write-Host '         not pushed to GitHub). Docker Desktop will not work without WSL.' -ForegroundColor Yellow
    if ((Read-Answer "Type 'yes' to continue") -ne 'yes') { Write-Host 'Aborted. Nothing was changed.'; exit 3 }
} elseif ($interactive -and -not $dryRun -and -not $assumeYes) {
    if ((Read-Answer 'Proceed? [y/N]') -notmatch '^(y|yes)$') { Write-Host 'Aborted. Nothing was changed.'; exit 3 }
}

if (-not $dryRun) {
    Start-Transcript -Path (Join-Path $PSScriptRoot 'win-tools-log.txt') -Append | Out-Null
}

# ---------- Actions ----------
$script:rebootNeeded = $false

function Install-Tool([string]$key) {
    $t = $tools[$key]
    if ($status[$key].Installed) { Write-Host "${prefix}$($t.Title) is already installed - skipping."; return }
    if ($hasWinget) {
        $cmd = "winget install --id $($t.Winget) --exact --silent --accept-package-agreements --accept-source-agreements"
        if ($dryRun) { Write-Host "${prefix}$cmd"; return }
        winget install --id $t.Winget --exact --silent --accept-package-agreements --accept-source-agreements
    } else {
        if ($dryRun) { Write-Host "${prefix}choco install $($t.Choco) -y"; return }
        choco install $t.Choco -y
    }
}

function Uninstall-Tool([string]$key) {
    $t = $tools[$key]
    $s = $status[$key]
    if (-not $s.Installed) { Write-Host "${prefix}$($t.Title) is not installed - skipping."; return }
    switch ($s.Via) {
        'Chocolatey' {
            # --remove-dependencies also removes the *.install packages (git.install, vscode.install)
            if ($dryRun) { Write-Host "${prefix}choco uninstall $($t.Choco) -y --remove-dependencies"; return }
            choco uninstall $t.Choco -y --remove-dependencies
        }
        'winget' {
            if ($dryRun) { Write-Host "${prefix}winget uninstall --id $($t.Winget) --exact --silent"; return }
            winget uninstall --id $t.Winget --exact --silent --accept-source-agreements
        }
        default {
            Write-Host "$($t.Title) was not installed by winget or Chocolatey. Remove it in Settings > Apps > Installed apps." -ForegroundColor Yellow
        }
    }
}

function Set-DockerGroup([string]$mode) {   # mode: add | remove
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $group = Get-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue
    if ($mode -eq 'add') {
        if (-not $group) { return }
        $isMember = Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $user }
        if ($isMember) { return }
        if ($dryRun) { Write-Host "${prefix}Add $user to docker-users"; return }
        Add-LocalGroupMember -Group 'docker-users' -Member $user -ErrorAction SilentlyContinue
        Write-Host "Added $user to docker-users (sign out and back in to apply)."
        return
    }
    if (-not $group) { return }
    $isMember = Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $user }
    if ($isMember) {
        if ($dryRun) { Write-Host "${prefix}Remove $user from docker-users" }
        else { Remove-LocalGroupMember -Group 'docker-users' -Member $user -ErrorAction SilentlyContinue }
    }
    $remaining = @(Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $user })
    if ($remaining.Count -eq 0) {
        if ($dryRun) { Write-Host "${prefix}Delete the now-empty docker-users group" }
        else { Remove-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue }
    }
}

function Uninstall-Wsl {
    if ($dryRun) {
        Write-Host "${prefix}wsl --shutdown"
        Write-Host "${prefix}wsl --unregister <each distro>   (deletes its files)"
        Write-Host "${prefix}wsl --uninstall"
        Write-Host "${prefix}Disable Windows features: Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform"
        return
    }
    wsl --shutdown
    foreach ($d in (Get-WslDistros)) {
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
    $script:rebootNeeded = $true
}

foreach ($k in $plan) {
    Write-Host "`n=== $($tools[$k].Title) ===" -ForegroundColor Cyan
    if ($action -eq 'install') {
        if ($k -eq 'wsl') {
            $installer = Join-Path $repoRoot '01-install-wsl.ps1'
            if ($dryRun) { Write-Host "${prefix}run $installer" } else { & $installer }
        } else {
            Install-Tool $k
            if ($k -eq 'docker') { Set-DockerGroup 'add' }
        }
    } else {
        switch ($k) {
            'wsl'    { Uninstall-Wsl }
            'docker' {
                if ($dryRun) { Write-Host "${prefix}Stop Docker Desktop if running" }
                else { Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue | Stop-Process -Force }
                Uninstall-Tool $k
                Set-DockerGroup 'remove'
            }
            default  { Uninstall-Tool $k }
        }
    }
}

if (-not $dryRun) { Stop-Transcript | Out-Null }

Write-Host ''
if ($dryRun) {
    Write-Host 'Dry run finished. Nothing was changed.' -ForegroundColor Green
} else {
    Write-Host 'Done.' -ForegroundColor Green
    if ($script:rebootNeeded) { Write-Host 'A REBOOT is required to finish removing WSL.' -ForegroundColor Yellow }
}
exit 0
