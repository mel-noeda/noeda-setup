# Working notes

Running log of findings and open items. They get folded into `README.md`, and later into the
noe repo's `developer-documentation`.

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

- Added `02-uninstall-tools.ps1`. It takes one flag per component plus `--all`, and errors on no
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
  and then copy it into Linux. `03-setup-ubuntu.sh` clones noe straight into `~/work/noe` over
  SSH, so the script is the only file they need. The noe docs should link to it and start at
  "Reopen in Container".
  - **Bootstrap problem:** a fresh machine has no Git on Windows and no GitHub login in Ubuntu
    (the script sets that up). With a private repo, the script cannot be downloaded without
    signing in. Options: (1) a **public** repo, ideally under `Noeda-AI`, allowing
    `curl -fsSL https://raw.githubusercontent.com/<org>/noeda-setup/main/03-setup-ubuntu.sh -o setup.sh && bash setup.sh`;
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
  - `03-setup-ubuntu.sh --mirror de` (any 2-letter country code) switches Ubuntu's sources to a
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
- Clean run of `03-setup-ubuntu.sh` (apt already done): **335 s**. Homebrew + gh + pyenv took
  about 3 min and the Python 3.12 build about 1 min.

- **A browser in Ubuntu for noe development: Chrome by default.** `03-setup-ubuntu.sh` installs
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

- [ ] Set global `git user.name` / `user.email` (still unset on this machine)
- [ ] Remove the unused Windows clone `C:\work\noe`
- [ ] Fold the README's _TBC_ sections into final text
