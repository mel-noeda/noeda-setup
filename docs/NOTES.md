# Working notes

History, findings and decisions behind this repo. The current, working procedure is in the
[README](../README.md), and the design is in [architecture.md](architecture.md). Read these notes
for the *why* and for problems already solved. Entries are dated and kept as written, so older
ones may describe things that have since changed.

**Names changed since these notes were written:**
`03-setup-ubuntu.sh` is now `02-setup-ubuntu.sh`; `02-uninstall-tools.ps1` is now
`scripts/win-tools.ps1` (it can install as well as remove); `01-install-tools.ps1` (Chocolatey,
Docker Desktop) no longer exists; see below. `02-setup-ubuntu.sh` no longer installs Homebrew, pyenv or Python (see 2026-11-24): the
developer sets up pyenv after cloning noe.

## Superseded: the Docker Desktop + Chocolatey approach (2026-11-20)

The first version of this repo (still readable with `git show main:README.md`) installed Git for
Windows, VS Code, Cursor and Docker Desktop with Chocolatey (`01-install-tools.ps1`), enabled
Docker Desktop's WSL integration for Ubuntu, signed in to GitHub with Git Credential Manager and
reused that credential in Ubuntu through `git-credential-manager.exe`. It worked, with caveats:

- Git inside the dev container asked for a GitHub login again, because only an SSH agent is
  forwarded into the container.
- Several tools had to be installed and kept in step on two operating systems.
- Docker Desktop brought its own engine, licence terms and clashes (see the last section).

It was replaced by the WSL-only setup: Windows keeps only WSL2, everything else is in Ubuntu.
Setup knowledge from that approach that still applies: expected, harmless Chocolatey warnings
were `pending system reboot`, `No registry key found based on 'Microsoft Visual Studio Code'` and
`Timeout waiting for Cursor process`. GCM lives under `ucrt64\bin` in Git for Windows 2.56+ and
`mingw64\bin` before. Virtualization shows as `VirtualizationFirmwareEnabled = False` once a
hypervisor runs, which is normal; check `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent`.
Docker Desktop on a company with more than 250 staff or $10M revenue needs a paid plan.


## 2026-11-20: first machine (Windows 11 Pro, Chocolatey)

### Findings

- **The dev container needs Linux paths.** `devcontainer.json` uses
  `"workspaceFolder": "${localWorkspaceFolder}"`, and the init scripts mount the checkout at the
  same path. A `C:\` checkout fails with
  `[UriError]: If a URI contains an authority component...`. The checkout must live in WSL
  (`~/work/noe`).
- **Editor server download on first WSL open.** VS Code and Cursor each download their server
  into WSL the first time they open a WSL folder. This is a one-time cost per editor version.
- **First image build** (`noe:main`) took **7 minutes** and produced a **6.4 GB** image
  (16 CPUs, fast connection).
- **GitHub credentials are not shared consistently.**
  - Windows: Git Credential Manager stores the token in Windows Credential Manager.
  - Ubuntu: worked by pointing `credential.helper` at the Windows GCM `.exe`
    (`/mnt/c/Program Files/Git/ucrt64/bin/git-credential-manager.exe`).
  - **Inside the dev container, `git pull` asked for a login again.** The host credentials are
    not passed through. The repo's container only forwards an **SSH agent** (`SSH_AUTH_SOCK`,
    see `.devcontainer/write_compose_local.sh` and
    `developer-documentation/docs/reference/devcontainers/docker-and-git.md`), and there was none
    on this machine. HTTPS credentials from the host do not reach the container.
- **Installing from inside the Claude desktop app (MSIX sandbox) hides per-user installs.**
  Cursor's files under `%LOCALAPPDATA%` were redirected into the app's package storage, so
  `cursor` was not found from WSL. Fix: run installers from a normal PowerShell.
- Docker Desktop needs **WSL integration** enabled for Ubuntu
  (Settings > Resources > WSL integration).

### Next: try a WSL-only setup

Idea: Windows keeps only **WSL2 + the editor** (VS Code and/or Cursor). Everything else goes
inside Ubuntu, so credentials and tools live in one place.

| Today (Windows) | WSL-only |
|---|---|
| Docker Desktop | Docker Engine (`docker-ce` from apt), `systemctl enable docker` |
| Git for Windows + GCM | `git` + `gh` in Ubuntu |
| HTTPS token via GCM | **SSH key + `ssh-agent` in WSL**. The dev container forwards the agent, so Git works inside the container too. |
| Chocolatey | Homebrew on Linux (matches the macOS docs in `tooling.md`), or apt |

Points to check:

- [ ] VS Code / Cursor: `dev.containers.executeInWSL` so Dev Containers uses Docker inside WSL
- [ ] `ssh-agent` running persistently in WSL (keychain, or a systemd user service) and seen by
      `write_compose_local.sh` (`SSH agent: mounted`)
- [ ] `git pull`/`push` inside the container work with no prompt
- [ ] WSL memory limit (`%UserProfile%\.wslconfig`) is large enough for Docker + the build
- [ ] Docker starts automatically with WSL (Ubuntu has `systemd=true`)
- [ ] Remove Docker Desktop and Git for Windows, and check that nothing on Windows still needs them

## 2026-11-23

- Added `scripts/win-tools.ps1` (then called `02-uninstall-tools.ps1`). It takes one flag per component plus `--all`, and errors on no
  flags or an unknown flag. `--dry-run` was tested for every flag. The real uninstall has **not**
  been run yet. It will run for real when this machine is switched to the WSL-only setup
  (probably `--docker --git`, keeping WSL and the editors).

- **Confusing: two "work" folders.** In Ubuntu, `~` is `/home/<you>` on WSL's own Linux disk. It is
  not `C:\`. `~/work/noe` (Linux) and `C:\work\noe` = `/mnt/c/work/noe` (Windows) are different
  folders. From Windows, reach Linux files at `\\wsl.localhost\Ubuntu\home\<you>`. For the docs:
  explain this early, use a distinct name (or say "Linux home" every time), and keep all code on
  the Linux side. To consider: move `noeda-setup` into `~/work` as well, and delete the old
  `C:\work\noe`.
- **Start search → "Ubuntu" can open the Microsoft Store.** `wsl --install -d Ubuntu` no longer
  uses the Store app. Windows search also shows the Store listing, which can rank first. Do not
  install it. Open Ubuntu from the Windows Terminal ˅ menu, with `wsl ~` (Win+R), or from the
  search result labelled *App*.

- **Keep the setup repo separate from noe.** A new developer should never clone noe on Windows
  and then copy it into Linux. `02-setup-ubuntu.sh` clones noe straight into `~/work/noe` over
  SSH, so the script is the only file they need. The noe docs should link to it and start at
  "Reopen in Container".
  - **Bootstrap problem:** a fresh machine has no Git on Windows and no GitHub login in Ubuntu
    (the script sets that up). With a private repo, the script cannot be downloaded without
    signing in. Options: (1) a **public** repo, ideally under `Noeda-AI`, allowing
    `curl -fsSL https://raw.githubusercontent.com/<org>/noeda-setup/main/02-setup-ubuntu.sh -o setup.sh && bash setup.sh`;
    (2) a private repo, with the file downloaded through the browser and run from `/mnt/c/...`;
    (3) a download on the docs site. **Decision pending.**

- **Execution policy blocks `.\script.ps1`** ("running scripts is disabled on this system").
  `Set-ExecutionPolicy -Scope Process` only applies to the window it was run in, so it is easy to
  miss. In the docs, always use the one-line form:
  `powershell -ExecutionPolicy Bypass -File .\01-install-wsl.ps1`. It changes no system setting.

- **Fresh machine: `wsl --install -d Ubuntu` takes two runs.** The first run installs WSL 3.0.5
  and enables VirtualMachinePlatform, then needs a reboot. Ubuntu itself is installed only when
  the command runs again after the reboot. `01-install-wsl.ps1` now checks for Ubuntu and says
  "reboot, then run again" when it is missing.

- **`apt-get update` "hangs" = slow WSL NAT networking (root cause of both stalls).**
  Measured from the same mirror: Windows 3.2 MB/s, WSL (NAT) **31 KB/s**. Also,
  `archive.ubuntu.com` itself was timing out (from Windows too), while `de.archive.ubuntu.com`
  answered in 0.1 s. Fixes:
  - `%UserProfile%\.wslconfig` with `[wsl2] networkingMode=mirrored` and `dnsTunneling=true`,
    then `wsl --shutdown`. WSL went to **4.4 MB/s**. `01-install-wsl.ps1` now writes this file
    when none exists.
  - `02-setup-ubuntu.sh --mirror de` (any 2-letter country code) switches Ubuntu's sources to a
    country mirror. apt now retries, with 30 s timeouts.

- **Linux `cursor` launcher blocks on a hidden prompt in WSL.** `/usr/bin/cursor` detects WSL
  and asks "Do you want to continue anyway? [y/N]", recommending the Windows app. Our script
  sent stderr to `/dev/null`, so `cursor --version` seemed to hang. Fix: set
  `DONT_PROMPT_WSL_INSTALL=1` (the script exports it, and it is also in the `~/.bashrc` block
  and `~/.config/environment.d`). Using the Linux editors is deliberate in this setup.
- apt with mirrored networking + the `de` mirror: **527 MB in 22 s (23.5 MB/s)**.

- **WSL popup: "using git on Windows drives… consider moving your work to the Linux drive".**
  It came from running the script inside `/mnt/c/work/noeda-setup`, which is a Git repo on `C:`.
  noe itself is correctly on Linux (`~/work/noe`). Action: move `noeda-setup` to
  `~/work/noeda-setup` and commit/push from there. A new developer only runs the downloaded
  script and never has a repo on `/mnt/c`.

- **Cursor "Log in" did nothing.** Linux Cursor opens the login page with `xdg-open`, and no
  browser was configured. `wslu` (`wslview`) is **not packaged for Ubuntu 26.04**, so the
  script now installs `~/.local/bin/windows-browser`. It calls
  `/mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler <url>` by full path, which
  works with `appendWindowsPath=false`. The script registers it with `xdg-mime` as the
  http/https handler and sets it as `BROWSER` (in `~/.bashrc` and
  `~/.config/environment.d/noeda.conf`).
- `gh` warns "Authentication credentials saved in plain text": WSL has no desktop keyring, so
  the token is in `~/.config/gh/hosts.yml` (mode 600). This is acceptable for a personal
  workstation; document it. The SSH key is protected by its passphrase.
- Clean run of `02-setup-ubuntu.sh` (apt already done): **335 s**. Homebrew + gh + pyenv took
  about 3 min and the Python 3.12 build about 1 min.

- **A browser in Ubuntu for noe development: Chrome by default.** `02-setup-ubuntu.sh` installs
  a Linux browser, so dev logins and cookies (`dev@example.com` on `localhost:5173`, staging)
  stay apart from everyday Windows browsing. WSLg rendering quirks were judged acceptable.

  | Option | Result |
  |---|---|
  | *(none)* | **Google Chrome** from Google's apt repo. Falls back to Firefox on non-amd64 machines (Google ships no Chrome build there). |
  | `--browser chrome` | Same, explicitly |
  | `--browser firefox` | Firefox from Mozilla's apt repo, pinned (`/etc/apt/preferences.d/mozilla`) above Ubuntu's `firefox` package, which only installs the snap |
  | `--nobrowser` | No Linux browser; links go to the **Windows** default browser through `~/.local/bin/windows-browser` |

  - The chosen browser becomes the `xdg-mime` http/https handler and `BROWSER` (in `~/.bashrc`
    and `~/.config/environment.d/noeda.conf`). Cursor/VS Code sign-in and `gh` open in it.
  - The choice is remembered in `~/.config/noeda-setup/browser`. A rerun without an option keeps
    it, so a `--nobrowser` user is not switched to Chrome later. (A saved `windows` from an
    earlier script version is read as `--nobrowser`.)
  - Switching to `--nobrowser` does **not** uninstall a browser installed earlier. The script
    says so, and the help text gives `sudo apt remove google-chrome-stable` / `firefox`.
  - Chrome: `/etc/default/google-chrome` (`repo_add_once="false"`) stops the package adding a
    second apt source. Verified on this machine: only `google-chrome.sources` exists.
  - Chromium was skipped: Ubuntu only offers it as a snap.
  - Tested: option errors (missing value, unknown value, `--browser windows`, both options
    given) exit 2; default/remembered/override cases resolve correctly. A real Chrome install
    (`--browser chrome`) ran on this machine and became the default for links. The
    `--nobrowser` and `--browser firefox` installs have **not** been run for real yet.

- **Dual boot: Windows clock exactly 1 h behind.** Linux stores UTC in the motherboard clock;
  Windows reads it as local time (CET = UTC+1). Windows time sync had also never run ("Local
  CMOS Clock, not synchronized"). WSL takes its clock from Windows, so a wrong clock can break
  apt ("Release file is not valid yet") and TLS/sign-ins. Fix (admin PowerShell, run by the
  user): `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`,
  then Settings > Date & time > Set time automatically > Sync now. No reboot was needed.
  Belongs in the README's troubleshooting section.

### Other open items

- [x] Set global `git user.name` / `user.email` (done in Ubuntu by `02-setup-ubuntu.sh`; Windows has no Git any more)
- [ ] Remove the unused Windows clone `C:\work\noe`

## 2026-11-24: Homebrew and pyenv removed from the setup

- **Decision:** `02-setup-ubuntu.sh` no longer installs Homebrew, `pyenv` or any Python. The
  developer sets up pyenv after cloning noe, following the noe docs.
- **Why:** pyenv from Homebrew on Linux worked badly. Homebrew itself was only there to supply
  `gh` and `pyenv`, and it added about 3 minutes and a large install under `/home/linuxbrew`.
  Earlier problems with this route: the Python version was read from noe's `dev/versions.env`
  before noe had been cloned, so the pin was ignored on a first run (a review finding on PR #1),
  and Python had to be built against Ubuntu's libraries with Homebrew kept off `PATH`.
- **`gh` now comes from GitHub's own apt repository**, as in the
  [official Debian/Ubuntu instructions](https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian):
  keyring `/etc/apt/keyrings/githubcli-archive-keyring.gpg`, source
  `/etc/apt/sources.list.d/github-cli.list`. It installs in the same `apt` run as Docker, VS Code
  and Cursor, and updates with `sudo apt update && sudo apt install gh`.
  The keyring file holds two keys. The 2022 key shows as expired (2026-09-05) and a key from
  2026-04-07 signs the repository now, so `gpg --show-keys` warns, but `apt` works.
- **Kept on purpose:** the apt build libraries for Python (`libssl-dev`, `zlib1g-dev`,
  `libbz2-dev`, `libreadline-dev`, `libsqlite3-dev`, `libncursesw5-dev`, `tk-dev`, `libxml2-dev`,
  `libxmlsec1-dev`, `libffi-dev`, `liblzma-dev`, `xz-utils`), so a later `pyenv install` just works.
- The `~/.bashrc` block no longer has the `brew shellenv` and `pyenv init` lines. Because the
  block is rewritten on every run, a machine set up earlier loses them when the script runs
  again. Homebrew itself is **not** uninstalled by the script; remove it by hand if wanted.
- **Not yet tested:** a full run on a fresh WSL install after this change.

## 2026-11-24: design option, the same setup on macOS and Linux hosts

Question: can the WSL idea (all of noe's tooling in one Linux VM that you shut down after work,
with the host almost untouched) work on a Mac, and on a Linux host?

### macOS

A Mac needs a Linux VM for Docker anyway: containers are Linux processes, and Docker Desktop,
OrbStack and Colima all run a hidden Linux VM. noe already supports macOS directly
(`developer-documentation/docs/howto/tooling.md` recommends **Colima**; `write_compose_local.sh`
handles Colima, OrbStack and Docker Desktop). That route keeps the checkout and the tools on
macOS. The option here goes further: **the checkout and all tools live inside the VM**, like
WSL, and macOS only has the VM tool and the editor.

| Tool | What it is | Fit |
|---|---|---|
| **Lima** (`limactl`) | Open-source lightweight Linux VMs (Apple `vz`), SSH set up for you | Closest free equivalent of WSL; scriptable. **Recommended.** |
| **OrbStack** | Commercial app: Linux machines + Docker, very fast, well integrated | Feels most like WSL. Paid licence for commercial use. |
| Colima | Docker runtime built on Lima | Docker only, not a dev VM; this is noe's current macOS route |
| Multipass | Canonical's Ubuntu VMs | Simple; Ubuntu only |
| UTM / Parallels / VMware Fusion | Full desktop VMs | Heavier; full Linux desktop if wanted |
| Apple `container` | Apple's tool, one small VM per container (macOS 26, Apple silicon) | Too new; Dev Containers support unclear |

**Differences from WSL:**

- **No WSLg.** Linux GUI apps cannot show on the Mac desktop nicely (XQuartz is clunky). So the
  **editor runs on macOS** and connects to the VM with **Remote-SSH**, then *Reopen in
  Container* runs on the VM's Docker. No Linux browser or `windows-browser` opener is needed:
  links open in the macOS browser.
- **Apple silicon is arm64.** noe's images and dependencies must build for arm64; Lima and
  OrbStack can run amd64 binaries through Rosetta if needed. Chrome has no arm64 Linux build,
  but the headless route installs no browser.
- **The VM user must be uid 1000.** noe's container user `vscode` is uid 1000, and the checkout
  and the SSH agent socket are bind-mounted from the VM. On WSL the first user is uid 1000
  already. Lima defaults to the macOS uid (usually 501), and OrbStack uses it too, which would
  make the checkout and the agent socket unwritable in the container. The Lima sketch sets
  `user.uid = 1000`; the OrbStack sketch creates a separate machine user with uid 1000.
- **The editor's server starts over a non-interactive SSH session**, which does not read the
  `~/.bashrc` block. noe's `devcontainer_init.sh` mounts the `SSH_AUTH_SOCK` it sees, so
  `--headless` lets sshd set it for every session (`~/.ssh/environment` with
  `PermitUserEnvironment SSH_AUTH_SOCK`) and enables systemd linger so the agent keeps running.
- **Naming:** noe's scripts choose their Docker and SSH handling from the daemon's host name
  (`docker info --format '{{.Name}}'`). A VM named `colima`, `orbstack` or `docker-desktop`
  would take the wrong branch; the sketches refuse those names.

**What carries over:** keep the checkout on the VM's own disk (shared Mac folders are slow, like
`/mnt/c`); stop the VM to free its CPU and memory (`limactl stop noe`, like `wsl --shutdown`);
delete it to remove nearly everything (`limactl delete noe`).

**Sketched in this repo (untested, no Mac available yet):**

| File | Does |
|---|---|
| `macos/01-install-lima.sh` | Installs Lima with Homebrew; creates VM `noe` from `template://ubuntu-lts` (`vz`, Rosetta on arm64, no host mounts, uid 1000, no agent forwarding); copies in and runs `02-setup-ubuntu.sh --headless`; adds `Include ~/.lima/*/ssh.config` to the top of `~/.ssh/config`; installs Remote-SSH and Dev Containers in Cursor/VS Code if their CLIs exist |
| `macos/01-install-orbstack.sh` | Installs OrbStack (cask); creates machine `noe`; creates or reuses a uid-1000 user; runs `02-setup-ubuntu.sh --headless` from `/Users/...` (OrbStack shares Mac files); editor extensions as above |
| `02-setup-ubuntu.sh --headless` | No WSL checks or `wsl.conf`, no VS Code/Cursor, no browser; installs Docker Engine, `gh`, Git, SSH key/agent, clones noe; sshd `SSH_AUTH_SOCK` + linger; prints Remote-SSH next steps |

**Open questions for the first Mac test:**

- [ ] Lima: does `--set '.user.uid = 1000'` work in the installed Lima version, and does
      `template://ubuntu-lts` give 26.04 (with Ubuntu's `ssh-agent.socket` user unit)?
- [ ] Which `SSH_AUTH_SOCK` does the editor's server see in the VM (`echo $SSH_AUTH_SOCK` in a
      Remote-SSH terminal), and does `write_compose_local.sh` report *SSH agent: mounted*?
- [ ] OrbStack: does `ssh dev@noe@orb` go through OrbStack's own SSH proxy (so
      `~/.ssh/environment` is ignored) and forward the macOS agent instead? Is Docker Engine
      inside a machine fine next to OrbStack's own engine?
- [ ] noe image build and tests on arm64.
- [ ] Cursor's and VS Code's Remote-SSH extension IDs (`anysphere.remote-ssh`,
      `ms-vscode-remote.remote-ssh`).
- [ ] Git pull/push inside the dev container (as for WSL).

### Linux host

Not silly, but less needed. On Linux, noe's dev container runs on the host's own Docker Engine,
so the extra layer is optional. Options, lightest first:

| Option | Host gets | Notes |
|---|---|---|
| **Directly on the host** | Docker Engine, Git, `gh`, editor | noe's standard Linux route. The dev container already isolates the toolchain; the host keeps Docker, the `docker` group (root-equivalent) and the editor. |
| **Lima on Linux** (KVM/QEMU) | Lima only (+ editor) | Same `01-install-lima.sh` idea and `02-setup-ubuntu.sh --headless`; one documented route for Mac and Linux. |
| **Incus/LXD system container** | Incus | Full Ubuntu with systemd, shares the host kernel, starts in a second; Docker inside needs `security.nesting=true`. |
| Multipass, GNOME Boxes, virt-manager | the VM tool | Full VMs; Multipass is the simplest |
| distrobox / toolbox | podman | Shares your home directory and is built for convenience, not isolation; not this goal |

Recommendation if a VM is wanted on Linux: **Lima**, so Mac and Linux share one route and one
script. Otherwise install directly; the uid-1000 rule applies there too (the first user on most
distros is uid 1000).

## Reference: a dev container compared with a dev VM

Written 2026-11-24 in answer to: "If I install tools in the dev container, are they kept after
I shut it down? How close is a dev container to a real Linux dev box?"

**What survives (noe's dev container):**

| Action | Tools you installed in the container (`apt`, `pip --user`, files under `/home/vscode`) | Checkout | Named volumes (`noe-state`, `pnpm-store`, `frontend-node-modules`) |
|---|---|---|---|
| Close the editor (`shutdownAction: stopCompose`) | **Kept**: the container is stopped, not removed | Kept | Kept |
| Restart the VM / `wsl --shutdown` | Kept | Kept | Kept |
| **Rebuild Container**, a new image (Dockerfile or toolchain change), `docker compose down` | **Lost**: a new container starts from the image | Kept (bind mount from the VM) | Kept |
| Switch branch | Treat as **lost**: the image is tagged per branch (`noe:<branch>`), so the container is likely recreated from another image | Kept | Kept |
| A second checkout folder | Its own container and copy | Separate | Separate per Compose project, except the shared `noe-dev-pnpm-store` |

So treat the container's own filesystem as disposable. To keep a tool:

- **For everyone:** add it to the image (`.devcontainer/Dockerfile`, `install_toolchain.sh`) or
  to `devcontainer_post_create.sh`.
- **Just for you:** a dotfiles repository (the Dev Containers *Dotfiles: Repository* setting
  clones it and runs its install script in every new container), or install it in the VM
  instead, outside the container.

**How close it is to a real Linux box:**

- **Same:** a full Ubuntu user space, `apt`, a normal shell, your own user (`vscode`) with sudo,
  the real Linux kernel of the VM.
- **Different:**
  - **No systemd or services**: PID 1 runs `sleep infinity`, so `systemctl` does not work.
    Postgres, Redis, OpenFGA and Dapr run as separate containers in the same Compose project.
  - **No GUI**; only the folders that are mounted are shared with the VM.
  - **Docker is the VM's engine**, reached through the mounted `/var/run/docker.sock`. Containers
    you start from inside (Testcontainers) are siblings, not nested.
  - **Networking**: its own network namespace; ports reach the host only where published
    (5173, 8000, 8001, 9090 on `127.0.0.1`).
  - **Ephemeral by design**: a rebuild resets it, which is the point: everyone gets the same
    toolchain, and a broken container is fixed by rebuilding.

The two layers do different jobs: **the VM** (WSL, Lima, OrbStack) keeps noe's tooling off the
host and can be switched off; **the dev container** pins the project's toolchain so every
developer gets the same one. The VM is the dev box; the container is the project's toolbox.

## Reference: how Docker runs in the WSL-only setup

Written 2026-11-23 in answer to: "Does WSL run as a Docker container? Where do the containers
run? Can Docker Desktop on Windows see them? Would reinstalling Docker Desktop clash?"
Intended for the README / developer docs.

### What runs where

```
Windows 11
└─ WSL2 utility VM (a small Hyper-V virtual machine with a real Linux kernel)
   └─ Ubuntu (the distro)                       ← code in ~/work/noe, Cursor/VS Code, Chrome
      ├─ dockerd + containerd (systemd services)  ← Docker Engine, installed by 02-setup-ubuntu.sh
      │   socket: /var/run/docker.sock
      └─ containers: noe workspace, postgres, openfga, redis, dapr …
```

- **WSL2 is not a Docker container.** It is a lightweight **virtual machine** that Windows
  manages, running a real Linux kernel. Each distro (Ubuntu) runs inside that one VM, kept
  separate from other distros, but it is not Docker.
- **Docker Engine runs inside Ubuntu.** `dockerd` is an ordinary systemd service there.
  Containers are Linux processes in the same VM, isolated the usual Docker way. There is no
  extra VM per container.
- **The dev container uses that same engine.** The editor runs `docker compose` in Ubuntu, and
  `/var/run/docker.sock` is passed into the workspace container, so Testcontainers-based tests
  start their containers on the same engine.

### Seeing the containers from Windows

Docker Desktop's GUI **cannot** show them: it only manages its own engine (in its own
`docker-desktop` WSL distro) and has no option to attach to another engine. Alternatives:

| Option | Notes |
|---|---|
| `docker ps` in an Ubuntu terminal | The direct way |
| **Containers (Docker) extension** in Linux VS Code / Cursor | GUI for containers, images, logs, shells. noe's devcontainer already lists `ms-azuretools.vscode-docker`; also install it in the Linux editor. |
| `wsl docker ps` from Windows PowerShell | Runs Ubuntu's `docker` command from Windows; no setup needed |
| `lazydocker` (`brew install lazydocker`) | Full-screen terminal dashboard |
| Windows `docker` CLI with a context pointing at Ubuntu | Possible over SSH (needs `sshd` in Ubuntu); more setup than it is worth |

### Reinstalling Docker Desktop on Windows: it can clash

With Docker Desktop's default setting (WSL integration on for the default distro):

1. **It takes over the `docker` command in Ubuntu.** Desktop adds its own `docker` CLI there,
   which talks to *Desktop's* engine. The same command then reaches a different engine with a
   different image cache, so containers and the `noe:main` image seem to disappear.
2. **It rewrites `~/.docker/config.json`** to use `"credsStore": "desktop.exe"`, which breaks
   registry pulls when Desktop is not running. (`02-setup-ubuntu.sh` moves such a file aside.)
3. **noe's devcontainer scripts change behaviour** when the engine reports `docker-desktop`,
   for example in where `write_compose_local.sh` looks for the SSH agent socket.
   `02-setup-ubuntu.sh` deliberately stops in that situation.
4. **Ports collide.** With mirrored networking both engines publish on Windows `localhost`, so
   two stacks cannot both use 5173, 8000 or 9090.
5. **Resources and licensing.** Two engines in two VMs, plus Docker Desktop's subscription terms
   for larger companies (more than 250 staff or $10M revenue).

**If Docker Desktop is needed for something else**, it can coexist. In Docker Desktop, go to
**Settings > Resources > WSL integration**, turn off **"Enable integration with my default WSL
distro"**, and leave **Ubuntu** unticked. Each side then keeps its own engine: Windows tools use
Desktop's, and Ubuntu keeps its own `docker` command and `dockerd`. Desktop still will not show
Ubuntu's containers.

**Recommendation for noe:** no Docker Desktop. Use the Containers extension or `lazydocker` for
a visual view.
