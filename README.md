# Noeda developer workstation setup (Windows)

Sets up a Windows 11 PC to develop on [`Noeda-AI/noe`](https://github.com/Noeda-AI/noe) with
Dev Containers. **You need nothing installed beforehand except PowerShell.**

Two scripts do the work:

| Script | Runs in | Does |
|---|---|---|
| [`01-install-wsl.ps1`](01-install-wsl.ps1) | Windows (admin PowerShell) | Installs WSL2 and Ubuntu |
| [`02-setup-ubuntu.sh`](02-setup-ubuntu.sh) | Ubuntu | Installs everything else inside Ubuntu and clones noe |

Everything lives inside Ubuntu: Docker, Git, editors, browser, and the code. Windows only hosts
WSL. The stack and the order of events are drawn in [docs/architecture.md](docs/architecture.md).

## What you need

- Windows 11 (tested on Pro, build 26300), 16 GB RAM or more, and local administrator rights.
- CPU virtualization turned on in the BIOS/UEFI (Intel VT-x or AMD-V/SVM).
- A GitHub account that is a member of the `Noeda-AI` organisation.
- An internet connection. Step 3 downloads roughly 500 MB of packages; the first container build adds a 6 GB image.

## Setup

### 1. Download

On the GitHub page of this repository, choose **Code > Download ZIP**, then extract it anywhere
(for example in Downloads).

### 2. Install WSL and Ubuntu (Windows)

Open **PowerShell as administrator** (Start menu, type *PowerShell*, right-click, *Run as
administrator*). Go to the extracted folder (type `cd `, then drag the folder into the window)
and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\01-install-wsl.ps1
```

On a fresh machine this takes two runs:

1. The first run installs WSL. It then tells you to **reboot**.
2. After the reboot, run the same command again. It installs Ubuntu and, when asked, you create a
   **Linux username and password**. They are local to WSL and unrelated to your Windows or
   GitHub account. You need the password for `sudo`.

When it says *Ubuntu is installed*, it prints the exact command for the next step.

### 3. Set up Ubuntu

Open **Ubuntu** (Windows Terminal, the down-arrow menu, *Ubuntu*; or press Win+R and run
`wsl ~`). Run the command printed by step 2. It looks like this:

```bash
bash '/mnt/c/Users/<you>/Downloads/noeda-setup/02-setup-ubuntu.sh' 2>&1 | tee ~/setup-ubuntu.log
```

It installs Docker Engine, VS Code, Cursor, Chrome, Git and the GitHub CLI, then creates
an SSH key, registers it on GitHub, and clones noe to `~/work/noe`. It asks you for:

1. your Linux password (for `sudo`),
2. your name and email for Git commits,
3. a passphrase for the new SSH key (recommended),
4. a GitHub sign-in: open the URL it shows, enter the code, and authorize.

It is safe to run again if anything fails or you want to update; every step checks what is
already there. If it ends with *Restart WSL*, run `wsl --shutdown` in PowerShell, then open
Ubuntu again.

The clone only works if your GitHub account has access to `Noeda-AI/noe`. If you don't have it
yet, ask an organisation admin, then run the script again.

### 4. Open noe in its dev container

In Ubuntu:

```bash
cd ~/work/noe
cursor .        # or: code .
```

Start the editor from this Ubuntu shell so it inherits your SSH agent. The window shows
**WSL: Ubuntu** at the bottom left. Press `Ctrl+Shift+P`, run **Dev Containers: Reopen in
Container**, and wait. The first build takes about 7 minutes and a 6 GB image.

Then, in a terminal inside the container, start the app (see the noe repo's
`developer-documentation/docs/howto/dev-containers.md` for details):

```bash
# These steps may vary if the Noe app is changed: the Noe Github repo is the source of truth for this
cd companion_backend
cp env.examples/.env.example .env      # first time only
./run_backend.sh --frontend --bootstrap dev@example.com
```

Open http://localhost:5173 and sign in as `dev@example.com`.

## Good to know

- **Your code is on the Linux side.** `~/work/noe` in Ubuntu is not `C:\work\noe`. From Windows,
  browse it at `\\wsl.localhost\Ubuntu\home\<you>\work\noe`. Keep all code there: the dev
  container needs Linux paths, and it is much faster than `C:`.
- **Git works inside the container** because your SSH agent is forwarded into it.
- **No Docker Desktop on Windows.** Docker Engine runs inside Ubuntu. Docker Desktop is not needed and can
  take over the `docker` command in Ubuntu. To see containers, use `docker ps` in Ubuntu or the
  Docker extension in the editor.
  It is possible to run your own Docker desktop on Windows if you need to for other reasons, but you must diable the "integrate with WSL option in your Docker Desktop settings. Further details are in the [NOTES](./docs/NOTES.md) file in the docs folder. 
- **Python and pyenv are not installed by this setup**, on Windows or in Ubuntu. Set up pyenv yourself after the clone, following the noe repo's own docs. The libraries pyenv needs to build Python (`libssl-dev`, `zlib1g-dev` and so on) are already installed.
- **NO IDEs or dev tools installed to Windows** This setup intentionally installs the tools and IDEs into WSL, with the idea that all development work takes place in that context. Paths, references, all of it stays the same as for standard No development on Mac or Linux, without the need for path rewriting or any specific logic to handle Windows architecture. This also means that that you can keep two identities: log in to your IDEs and tools using your Noeda account inside WSL, and install a separate instance of your favourite tools in Windows, allowing you to work on your personal projects in Widnows if you so wish. Orrrrrr you could simply install no developer tools whatsoever on your Windows box and keep it for your Call of Duty marathons, Sex and the City watch parties, Dance Dance Revolution dance-offs or whatever. It's all it's good for, really.

### Options for `02-setup-ubuntu.sh`

```bash
bash 02-setup-ubuntu.sh [--quiet] [--mirror CC] [--browser chrome|firefox | --nobrowser]
```

| Option | Effect |
|---|---|
| `--quiet` | Hide apt output |
| `--mirror de` | Use the Ubuntu mirror for a country (`de`, `ch`, `uk`, `us`, ...). Use it if `apt-get update` hangs at *Waiting for headers*. |
| `--browser chrome` (default) | Google Chrome in Ubuntu, a separate browser for noe logins and cookies |
| `--browser firefox` | Firefox from Mozilla's apt repository instead |
| `--nobrowser` | No browser in Ubuntu; links open in your Windows browser |

## Troubleshooting/Known Issues

| Symptom | Fix |
|---|---|
| `running scripts is disabled on this system` | Use the full command from step 2, with `-ExecutionPolicy Bypass`. It changes no system setting. |
| Start-menu search shows an *Ubuntu* Store app | Don't install it. Open Ubuntu from Windows Terminal, or run `wsl ~` (Win+R). |
| Downloads inside Ubuntu are very slow, or `apt` seems stuck | Run `wsl --shutdown`, then the script again, with `--mirror <country code>`. `01-install-wsl.ps1` already enables mirrored networking in `%UserProfile%\.wslconfig`. |
| `apt` says *Release file is not valid yet*, or sign-ins fail (dual boot with Linux) | The Windows clock is wrong. In an admin PowerShell: `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`, then *Settings > Time & language > Date & time > Sync now*. |
| `docker: permission denied` in Ubuntu | Run `wsl --shutdown` in PowerShell and reopen Ubuntu, so your new `docker` group applies. |
| *Reopen in Container* fails with `[UriError]` | You opened a Windows folder. Open the Ubuntu checkout: `cd ~/work/noe && cursor .`. The bottom left must show **WSL: Ubuntu**. |
| The script stops with *Docker Desktop is still providing 'docker'* | Remove Docker Desktop: `.\scripts\win-tools.ps1 --docker --uninstall`, then `wsl --shutdown`, then run the script again. |
| Virtualization or WSL errors at install | Enable Intel VT-x or AMD-V (SVM) in the BIOS/UEFI. |

More detail on every one of these is in [docs/NOTES.md](docs/NOTES.md).

## Managing/Cleaning up Windows tools

If a machine was set up the old way (Docker Desktop, Git for Windows and so on), or you want a
Windows tool back, use [`scripts/win-tools.ps1`](scripts/win-tools.ps1). It prints a table of
what is installed, then installs or removes the tools you pick. Run it from an admin PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1                      # table, then asks what to do
powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --gh --install
powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --docker --git --uninstall
powershell -ExecutionPolicy Bypass -File .\scripts\win-tools.ps1 --all --uninstall --dry-run
```

Tools: `--cursor --vscode --docker --git --gh --wsl` (or `--all`). Add `--dry-run` to see what
would happen without changing anything, `--list` for the table only, and `--help` for the rest.
Removing WSL deletes every distro and its files, so it asks you to type `yes` first.

## Documentation

- [docs/architecture.md](docs/architecture.md): the stack and the order of operations, as diagrams.
- [docs/NOTES.md](docs/NOTES.md): working notes, findings and history, including the earlier
  Docker Desktop approach and why it was dropped.
