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

### Other open items

- [ ] Set global `git user.name` / `user.email` (still unset on this machine)
- [ ] Remove the unused Windows clone `C:\work\noe`
- [ ] Fold the README's _TBC_ sections into final text
