# Noeda Developer Workstation Setup (Windows 11)

How to set up a new Windows 11 machine to develop on the Noeda codebase
(`github.com/Noeda-AI/noe`) with **Dev Containers** in VS Code or Cursor.

> Written while setting up the first machine (2026-11-20).
> The repo's own dev container docs are
> `developer-documentation/docs/howto/dev-containers.md`. They assume macOS.
> This page adds the Windows-specific steps.

## Why WSL2, and not a `C:\` checkout

The repo's `.devcontainer` runs bash scripts on the **host** (`initializeCommand`). It mounts the
checkout into the container **at the same path as on the host**, and uses that path as the
container working directory (`"workspaceFolder": "${localWorkspaceFolder}"`).

With a checkout on `C:\` this breaks. The scripts produce `/c/work/noe`, while the editor
expects `c:\work\noe` inside a Linux container. Bind mounts from the Windows drive are also
very slow for a monorepo.

**So on Windows the checkout lives inside a WSL2 Linux distro (Ubuntu)**, for example
`/home/<you>/work/noe`. The editor connects to WSL first and then reopens in the container.
Inside WSL everything behaves as on Linux.

```
Windows (VS Code / Cursor UI)
  └─ WSL2: Ubuntu  ── checkout: ~/work/noe, initializeCommand runs here
        └─ Docker Desktop engine (WSL2 backend)
              └─ Compose project noe-main: workspace + postgres, openfga, redis, dapr
```

---

## 0. Prerequisites

| Requirement | Notes |
|---|---|
| Windows 11 Pro (tested on build 26300) | |
| CPU virtualization enabled in BIOS/UEFI | After WSL is installed, `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` should be `True`. Ignore `VirtualizationFirmwareEnabled = False` once a hypervisor is running; Windows always reports it like that. |
| 16 GB+ RAM (32 GB+ recommended) | Docker + the infra stack + the build are memory-hungry |
| Local administrator rights | For Chocolatey, WSL and Docker installs |
| GitHub account with access to `Noeda-AI/noe` | The repo is **private** |
| [Chocolatey](https://chocolatey.org/install) installed | The only thing installed beforehand |

**Recommended:** create a System Restore point before you start
(`Start > "Create a restore point" > Create…`).

---

## 1. Install the tooling (one elevated script)

Script: [`01-install-tools.ps1`](01-install-tools.ps1)

From an **elevated** PowerShell (right-click > *Run as administrator*):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
C:\work\noeda-setup\01-install-tools.ps1
```

What it does:

1. `wsl --install --no-distribution` enables WSL2 and the Virtual Machine Platform.
2. `choco install`:

   | Package | Version tested | What |
   |---|---|---|
   | `git` | 2.56.1 | Git for Windows, including **Git Credential Manager** (GCM) |
   | `vscode` | 1.146.0 | Visual Studio Code |
   | `cursoride` | 3.30.14 | Cursor (per-user install, `%LOCALAPPDATA%\Programs\cursor`) |
   | `docker-desktop` | 4.99.0 | Docker Desktop (WSL2 backend) |

3. Adds the current user to the local `docker-users` group.
   Elevate using **your own** account. If you elevate with a different admin account,
   that account is added to the group instead.

A log goes to `install-log.txt` next to the script. Expected, harmless warnings:
`pending system reboot`, `No registry key found based on 'Microsoft Visual Studio Code'`,
`Timeout waiting for Cursor process`.

### ➜ Reboot

WSL2 and Docker Desktop do not work until Windows restarts.

---

## 2. Docker Desktop first run

1. Start **Docker Desktop** from the Start menu and accept the Subscription Service Agreement.
   Check whether your organisation needs a paid Docker plan (companies with more than 250 staff
   or more than $10M revenue). Docker Hub sign-in is optional.
2. Check that it works (PowerShell):

   ```powershell
   docker version
   docker run --rm hello-world
   ```

---

## 3. Install Ubuntu in WSL

```powershell
wsl --install -d Ubuntu
```

On first start it asks you to create a **Linux username and password**. These are local to
WSL and not linked to your Windows or GitHub account. You need the password for `sudo`.

Then in Docker Desktop: **Settings > Resources > WSL integration**, turn on **Ubuntu**, and click
**Apply & restart**. Check inside Ubuntu:

```bash
docker version
```

---

## 4. Editor extensions

```powershell
code --install-extension ms-vscode-remote.remote-wsl
code --install-extension ms-vscode-remote.remote-containers
```

Cursor ships its own equivalents (`anysphere.remote-wsl`, `anysphere.remote-containers`).
They are pre-installed, so Cursor needs nothing extra. Microsoft's remote extensions are not
licensed for Cursor.

---

## 5. GitHub sign-in (first time, on Windows)

The repo is private. Git Credential Manager (GCM, part of Git for Windows) handles sign-in.
Do it once from a normal Windows PowerShell. Cloning is the easiest trigger:

```powershell
git clone https://github.com/Noeda-AI/noe C:\work\noe-signin-test
```

1. The terminal prints `info: please complete authentication in your browser...`
2. In the browser: sign in to GitHub, complete 2FA, and **Authorize Git Credential Manager**.
3. The token is stored in **Windows Credential Manager** (`git:https://github.com`).

You can then delete that test clone. The real checkout lives in WSL (next step).

> This must run in an interactive terminal. Non-interactive shells fail with
> `terminal prompts disabled`.

## 6. Git inside Ubuntu, then clone

Open **Ubuntu** from the Start menu (or `wsl -d Ubuntu`) and run:

```bash
# Reuse the Windows GitHub sign-in: no separate credentials in Linux
git config --global credential.helper "/mnt/c/Program\ Files/Git/ucrt64/bin/git-credential-manager.exe"
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main

mkdir -p ~/work && cd ~/work
git clone https://github.com/Noeda-AI/noe
```

> GCM path: Git for Windows 2.56+ installs it under `ucrt64\bin`. Older versions use
> `mingw64\bin`. Check with
> `Get-ChildItem 'C:\Program Files\Git' -Recurse -Filter git-credential-manager.exe`.

Line endings are fine by default inside Linux. Don't set `core.autocrlf` there.

Git **inside the dev container** does not get these credentials. The repo's container mounts only
an SSH agent (see `developer-documentation/docs/reference/devcontainers/docker-and-git.md`).
_TBC: confirm how push/pull from inside the container works on Windows._

## 7. Open in the Dev Container

From the Ubuntu shell:

```bash
cd ~/work/noe
code .        # VS Code: opens a window connected to WSL ("WSL: Ubuntu" bottom-left)
# or
cursor .      # Cursor
```

Then press `Ctrl+Shift+P` and run **Dev Containers: Reopen in Container**.

What happens on open (from `.devcontainer/devcontainer.json`):

1. `initializeCommand` runs in WSL. It generates `.devcontainer/compose.local.yaml` and builds the
   image `noe:<branch>` (for example `noe:main`) locally. _TBC: first build took N min on this machine._
2. Compose starts **postgres, openfga, redis, dapr-placement, dapr-scheduler** and the
   **workspace** container (project name `noe-main`).
3. `postCreateCommand` runs `pnpm install` for the frontend and checks Docker access.

The application itself does **not** start automatically. In a terminal inside the container:

```bash
cd companion_backend
cp env.examples/.env.example .env      # first time in this checkout
./run_backend.sh --frontend --bootstrap dev@example.com
```

Open http://localhost:5173 and sign in as `dev@example.com` (local loopback issuer, no cloud
credentials needed). The full how-to is in the repo:
`developer-documentation/docs/howto/dev-containers.md`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Docker Desktop: "WSL 2 installation is incomplete" | Reboot, then run `wsl --update` in an elevated PowerShell |
| `docker: command not found` inside Ubuntu | Docker Desktop > Settings > Resources > WSL integration > enable Ubuntu |
| `docker: permission denied` on Windows | Sign out and back in, so the `docker-users` membership applies |
| `/bin/bash^M: bad interpreter` | Checkout has CRLF line endings. Clone inside WSL, not on `C:\` |
| `[UriError]: If a URI contains an authority component, then the path component must either be empty or begin with a slash` on Reopen in Container | You opened a **Windows** folder (for example `C:\work\noe`). The repo's `workspaceFolder` is `${localWorkspaceFolder}`, which must be a Linux path. Open the WSL checkout instead: in Ubuntu run `cd ~/work/noe && cursor .`, or from Windows run `cursor --remote wsl+Ubuntu /home/<you>/work/noe`. The bottom-left corner must show **WSL: Ubuntu** before you reopen in the container. |
| `cursor: command not found` in Ubuntu (while `code` works) | Cursor is a per-user install under `%LOCALAPPDATA%\Programs\cursor`. If the installer ran from inside a sandboxed (MSIX) app, such as the Claude desktop app's terminal, Windows redirected the files into that app's private storage. Reinstall from a normal elevated PowerShell (`choco install cursoride -y --force`), then open a new Ubuntu window. Check: `ls "$LOCALAPPDATA/Programs/cursor/resources/app/bin"` from Windows shows `cursor` and `cursor.cmd`. |
| `terminal prompts disabled` on clone | Run the clone in a normal interactive terminal |
| Virtualization errors | Enable Intel VT-x / AMD-V (SVM) in BIOS/UEFI |

## Rollback

```powershell
wsl --unregister Ubuntu          # deletes the distro and everything in it
choco uninstall docker-desktop cursoride vscode git -y
```

Or use the System Restore point from step 0.
