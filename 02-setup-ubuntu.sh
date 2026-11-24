#!/usr/bin/env bash
# Noeda developer workstation - set up Ubuntu in WSL2 with everything needed for noe.
#
# Run INSIDE Ubuntu as your normal user (not root). sudo will ask for your Linux password.
#   bash 02-setup-ubuntu.sh
#
# Safe to run again: every step checks what is already there.
# Interactive steps: sudo password, Git name/email, SSH key passphrase, GitHub sign-in.
#
# Installs / configures:
#   apt (official vendor repos): Docker Engine + Compose + Buildx, VS Code, Cursor, Git, build deps
#   Homebrew on Linux:           gh (GitHub CLI), pyenv. No Python is installed here; the noe stack
#                                installs and pins its own (the build deps above are for pyenv).
#   SSH:                         ed25519 key, systemd ssh-agent, key registered on GitHub.
#                                The noe dev container forwards this agent, so Git works inside it.
#   WSL:                         /etc/wsl.conf (systemd on, Windows PATH not appended)
#   Browser:                     Google Chrome in Ubuntu by default (Google's apt repo, not a snap), as a
#                                separate browser for noe development and the default for links.
#                                --browser firefox installs Firefox instead (Mozilla's apt repo).
#                                --nobrowser installs none: links go to the Windows default browser.

set -euo pipefail

NOE_DIR="${NOE_DIR:-$HOME/work/noe}"
NOE_REPO_SSH="git@github.com:Noeda-AI/noe.git"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BLOCK_BEGIN="# >>> noeda-setup >>>"
BLOCK_END="# <<< noeda-setup <<<"

QUIET=0
MIRROR=""
BROWSER_CHOICE=""
BROWSER_PREF_FILE="$HOME/.config/noeda-setup/browser"
USAGE="Usage: bash $(basename "$0") [--quiet] [--mirror CC] [--browser chrome|firefox | --nobrowser]
  --quiet          hide apt/brew output
  --mirror CC      use the Ubuntu country mirror CC.archive.ubuntu.com (e.g. de, ch, uk, us)
                   instead of archive.ubuntu.com - use it when 'apt-get update' hangs at
                   'Waiting for headers'

Browser - by default the script installs Google Chrome inside Ubuntu as a separate browser for
noe development (dev logins and cookies stay apart from your everyday Windows browser), and
makes it the default for links opened by Linux apps (Cursor/VS Code sign-in, gh, docs):
  --browser chrome   (default) Google Chrome, from Google's apt repo
                     (on non-amd64 machines, where Chrome is not available, Firefox is used)
  --browser firefox  Firefox, from Mozilla's apt repo (a .deb, not the snap)
  --nobrowser        install no browser in Ubuntu; links open in the Windows default browser
The choice is remembered for later runs. Switching to --nobrowser does not uninstall a browser
installed earlier - remove it with: sudo apt remove google-chrome-stable  (or: firefox)"
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=1 ;;
        --mirror)
            [ $# -ge 2 ] || { echo "ERROR: --mirror needs a country code, e.g. --mirror de" >&2; exit 2; }
            MIRROR="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift
            [[ "$MIRROR" =~ ^[a-z]{2}$ ]] || { echo "ERROR: --mirror expects a 2-letter country code, got '$MIRROR'" >&2; exit 2; } ;;
        --browser)
            [ $# -ge 2 ] || { echo "ERROR: --browser needs one of: chrome, firefox (or use --nobrowser)" >&2; exit 2; }
            [ -z "$BROWSER_CHOICE" ] || { echo "ERROR: give only one of --browser / --nobrowser" >&2; exit 2; }
            BROWSER_CHOICE="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift
            case "$BROWSER_CHOICE" in
                chrome|firefox) ;;
                *) echo "ERROR: --browser expects chrome or firefox, got '$BROWSER_CHOICE' (or use --nobrowser)" >&2; exit 2 ;;
            esac ;;
        --nobrowser)
            [ -z "$BROWSER_CHOICE" ] || { echo "ERROR: give only one of --browser / --nobrowser" >&2; exit 2; }
            BROWSER_CHOICE="nobrowser" ;;
        -h|--help) echo "$USAGE"; exit 0 ;;
        *) echo "ERROR: unknown option '$1'." >&2; echo "$USAGE" >&2; exit 2 ;;
    esac
    shift
done

# No --browser / --nobrowser given: keep the choice from an earlier run, else default to Chrome
# (Firefox on machines where Google ships no Chrome build, i.e. not amd64).
if [ -z "$BROWSER_CHOICE" ]; then
    BROWSER_CHOICE="$(cat "$BROWSER_PREF_FILE" 2>/dev/null || true)"
    case "$BROWSER_CHOICE" in
        chrome|firefox|nobrowser) ;;
        windows) BROWSER_CHOICE="nobrowser" ;;   # value written by an earlier version of this script
        *) if [ "$(dpkg --print-architecture)" = "amd64" ]; then BROWSER_CHOICE="chrome"
           else BROWSER_CHOICE="firefox"; fi ;;
    esac
fi

SCRIPT_START=$(date +%s)
step() { printf '\n\033[1;36m=== [%s +%ss] %s ===\033[0m\n' "$(date +%H:%M:%S)" "$(( $(date +%s) - SCRIPT_START ))" "$*"; }

# apt wrappers: full output by default, so you can see what is downloaded and installed.
apt_update() {
    if [ "$QUIET" -eq 1 ]; then sudo apt-get update -qq
    else sudo apt-get update; fi
}
apt_install() {
    printf '  Installing: %s\n' "$*"
    if [ "$QUIET" -eq 1 ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null
    else
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    fi
}
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33m  WARNING: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

NEEDS_WSL_RESTART=0

# The Linux 'cursor' (and 'code') launchers detect WSL and stop at a hidden
# "Do you want to continue anyway? [y/N]" prompt, recommending the Windows app instead.
# This setup deliberately runs the Linux editors through WSLg, so skip that prompt.
export DONT_PROMPT_WSL_INSTALL=1

# ---------------------------------------------------------------- preflight
step "Preflight"
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (the script uses sudo where needed)."
grep -qi microsoft /proc/version || die "This script is meant for Ubuntu inside WSL2."
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "Expected Ubuntu, found ${ID:-unknown}."
info "Ubuntu ${VERSION_ID} (${VERSION_CODENAME})"
[ -d /run/systemd/system ] || die "systemd is not running. Put 'systemd=true' under [boot] in /etc/wsl.conf, run 'wsl --shutdown' in Windows, then retry."

if command -v docker >/dev/null 2>&1 && [ "$(docker info --format '{{.Name}}' 2>/dev/null || true)" = "docker-desktop" ]; then
    die "Docker Desktop is still providing 'docker' here. Uninstall Docker Desktop on Windows first (.\scripts\win-tools.ps1 --docker --uninstall), then run 'wsl --shutdown' and retry."
fi

sudo -v || die "sudo is required."
ARCH="$(dpkg --print-architecture)"

# ---------------------------------------------------------------- wsl.conf
step "WSL settings (/etc/wsl.conf)"
ensure_wsl_conf() {   # section key value
    local section="$1" key="$2" value="$3"
    sudo touch /etc/wsl.conf
    if sudo grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${value}[[:space:]]*$" /etc/wsl.conf; then
        return 0
    fi
    if sudo grep -qE "^[[:space:]]*${key}[[:space:]]*=" /etc/wsl.conf; then
        sudo sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" /etc/wsl.conf
    elif sudo grep -qE "^\[${section}\]" /etc/wsl.conf; then
        sudo sed -i -E "/^\[${section}\]/a ${key}=${value}" /etc/wsl.conf
    else
        printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" | sudo tee -a /etc/wsl.conf >/dev/null
    fi
    NEEDS_WSL_RESTART=1
    info "set [${section}] ${key}=${value}"
}
ensure_wsl_conf boot systemd true
# Keep Windows programs (git.exe, code.exe, ...) out of the Linux PATH.
ensure_wsl_conf interop appendWindowsPath false

# ---------------------------------------------------------------- apt sources
step "apt sources"
# Fail and retry slow mirrors instead of waiting forever at "Waiting for headers".
printf 'Acquire::Retries "3";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' \
    | sudo tee /etc/apt/apt.conf.d/80noeda-network >/dev/null
UBUNTU_SOURCES=/etc/apt/sources.list.d/ubuntu.sources
if [ -n "$MIRROR" ]; then
    if [ -f "$UBUNTU_SOURCES" ]; then
        [ -f "$UBUNTU_SOURCES.orig" ] || sudo cp "$UBUNTU_SOURCES" "$UBUNTU_SOURCES.orig"
        sudo sed -i -E "s#https?://([a-z]{2}\.)?(archive|security)\.ubuntu\.com/ubuntu/?#http://${MIRROR}.archive.ubuntu.com/ubuntu/#g" "$UBUNTU_SOURCES"
        info "Ubuntu packages from http://${MIRROR}.archive.ubuntu.com/ubuntu/ (original saved as ubuntu.sources.orig)"
    else
        warn "$UBUNTU_SOURCES not found; --mirror ignored"
    fi
fi
grep -h '^URIs:' "$UBUNTU_SOURCES" 2>/dev/null | sort -u | sed 's/^/  /' || true

# ---------------------------------------------------------------- apt base
step "Base packages (apt)"
info "Refreshing package lists (first run on a new Ubuntu downloads ~200 MB)..."
apt_update
apt_install \
    ca-certificates curl gnupg git openssh-client procps file build-essential \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    xdg-utils
info "git $(git --version | awk '{print $3}')"

# ---------------------------------------------------------------- vendor apt repos
step "Vendor apt repositories (Docker, VS Code, Cursor)"
sudo install -d -m 0755 /etc/apt/keyrings /usr/share/keyrings

add_key() {   # url dest
    if [ ! -s "$2" ]; then
        curl -fsSL "$1" | sudo tee "$2" >/dev/null
        sudo chmod a+r "$2"
        info "key: $2"
    fi
}
write_source() {   # file content
    if [ ! -f "$1" ] || ! printf '%s\n' "$2" | sudo cmp -s - "$1"; then
        printf '%s\n' "$2" | sudo tee "$1" >/dev/null
        info "source: $1"
    fi
}

# Docker (https://docs.docker.com/engine/install/ubuntu/)
add_key https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.asc
write_source /etc/apt/sources.list.d/docker.sources "Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc"

# VS Code (https://code.visualstudio.com/docs/setup/linux). Same file and key names as
# Microsoft's instructions, so the package's own repo setup does not add a duplicate.
if [ ! -s /usr/share/keyrings/microsoft.gpg ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
    sudo chmod a+r /usr/share/keyrings/microsoft.gpg
    info "key: /usr/share/keyrings/microsoft.gpg"
fi
echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
write_source /etc/apt/sources.list.d/vscode.sources "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg"

# Cursor
add_key https://downloads.cursor.com/keys/anysphere.asc /etc/apt/keyrings/cursor.asc
write_source /etc/apt/sources.list.d/cursor.sources "Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/cursor.asc"

apt_update
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt_install code cursor

# ---------------------------------------------------------------- browser (optional)
step "Browser for development ($BROWSER_CHOICE)"
case "$BROWSER_CHOICE" in
    firefox)
        # Mozilla's own .deb (https://support.mozilla.org/kb/install-firefox-linux). Ubuntu's
        # 'firefox' package is only a wrapper that installs the snap, so pin Mozilla's repo higher.
        add_key https://packages.mozilla.org/apt/repo-signing-key.gpg /etc/apt/keyrings/packages.mozilla.org.asc
        write_source /etc/apt/sources.list.d/mozilla.sources "Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc"
        printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
            | sudo tee /etc/apt/preferences.d/mozilla >/dev/null
        apt_update
        apt_install firefox
        info "$(firefox --version 2>/dev/null || echo 'firefox installed')"
        ;;
    chrome)
        [ "$ARCH" = "amd64" ] || die "Google Chrome for Linux is only available for amd64 (this is $ARCH). Use --browser firefox."
        # Chrome's package adds its own apt source on install; we manage the source here instead,
        # so tell it not to (otherwise apt warns about two sources with different keys).
        printf 'repo_add_once="false"\nrepo_reenable_on_distupgrade="false"\n' | sudo tee /etc/default/google-chrome >/dev/null
        add_key https://dl.google.com/linux/linux_signing_key.pub /etc/apt/keyrings/google-chrome.asc
        write_source /etc/apt/sources.list.d/google-chrome.sources "Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/google-chrome.asc"
        apt_update
        apt_install google-chrome-stable
        info "$(google-chrome-stable --version 2>/dev/null || echo 'google-chrome-stable installed')"
        ;;
    nobrowser)
        info "--nobrowser: no Linux browser installed; links open in the Windows default browser."
        for pkg in google-chrome-stable firefox; do
            if dpkg -s "$pkg" >/dev/null 2>&1; then
                info "note: $pkg is still installed from an earlier run (remove with: sudo apt remove $pkg)"
            fi
        done
        ;;
esac
info "docker $(docker --version | awk '{print $3}' | tr -d ,), code $(code --version 2>/dev/null | head -1), cursor $(cursor --version 2>/dev/null | head -1)"

# ---------------------------------------------------------------- docker engine
step "Docker Engine"
sudo systemctl enable --now docker.service containerd.service >/dev/null 2>&1
if ! [[ " $(id -nG "$USER") " == *" docker "* ]]; then
    sudo usermod -aG docker "$USER"
    NEEDS_WSL_RESTART=1
    info "added $USER to group docker (takes effect after 'wsl --shutdown')"
fi
# Leftover from Docker Desktop's WSL integration: a credential helper that only exists on Windows.
if [ -f "$HOME/.docker/config.json" ] && grep -q 'desktop\.exe' "$HOME/.docker/config.json"; then
    mv "$HOME/.docker/config.json" "$HOME/.docker/config.json.docker-desktop.bak"
    info "moved Docker Desktop's ~/.docker/config.json aside (credsStore desktop.exe)"
fi
sudo docker run --rm hello-world >/dev/null && info "hello-world container ran"

# ---------------------------------------------------------------- homebrew
step "Homebrew"
if [ ! -x "$BREW_PREFIX/bin/brew" ]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
info "$(brew --version | head -1)"
for formula in gh pyenv; do
    if ! brew list --formula "$formula" >/dev/null 2>&1; then
        info "Installing (brew): $formula"
        if [ "$QUIET" -eq 1 ]; then brew install --quiet "$formula"; else brew install "$formula"; fi
    fi
done
info "gh $(gh --version | head -1 | awk '{print $3}'), pyenv $(pyenv --version | awk '{print $2}')"

# ---------------------------------------------------------------- shell setup
step "Shell setup (~/.bashrc)"
# Browser that Linux apps use for links (sign-ins, docs), from --browser.
case "$BROWSER_CHOICE" in
    firefox) BROWSER_DESKTOP="firefox.desktop";         BROWSER_CMD="firefox" ;;
    chrome)  BROWSER_DESKTOP="google-chrome.desktop";   BROWSER_CMD="google-chrome-stable" ;;
    *)       BROWSER_DESKTOP="windows-browser.desktop"; BROWSER_CMD="$HOME/.local/bin/windows-browser" ;;
esac
SSH_SOCK_LINE='export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/openssh_agent"'
BLOCK="$BLOCK_BEGIN
# Managed by noeda-setup/02-setup-ubuntu.sh - edits inside this block are overwritten.
eval \"\$($BREW_PREFIX/bin/brew shellenv)\"
export PYENV_ROOT=\"\$HOME/.pyenv\"
eval \"\$(pyenv init - bash)\"
# Linux VS Code/Cursor via WSLg on purpose: skip their 'install the Windows app instead' prompt.
export DONT_PROMPT_WSL_INSTALL=1
# systemd user ssh-agent (ssh-agent.socket). The noe dev container forwards this socket.
$SSH_SOCK_LINE
# Load the GitHub key once per WSL session (asks for its passphrase).
if [[ \$- == *i* ]] && [ -S \"\$SSH_AUTH_SOCK\" ] && [ -f \"\$HOME/.ssh/id_ed25519\" ]; then
    ssh-add -l >/dev/null 2>&1 || ssh-add \"\$HOME/.ssh/id_ed25519\"
fi
# Browser for links from gh, Cursor/VS Code sign-in, etc. (choose with --browser).
export BROWSER=\"$BROWSER_CMD\"
$BLOCK_END"
touch "$HOME/.bashrc"
tmp="$(mktemp)"
awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$HOME/.bashrc" > "$tmp"
printf '%s\n' "$BLOCK" >> "$tmp"
mv "$tmp" "$HOME/.bashrc"
info "managed block written"

# Browser bridge: Linux apps open links in the Windows default browser. wslu's 'wslview' does
# this on older Ubuntu releases but is not packaged for every release, so ship a tiny opener.
# It calls the Windows program by full path, which works with appendWindowsPath=false.
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cat > "$HOME/.local/bin/windows-browser" <<'OPENER'
#!/bin/sh
# Open URLs in the Windows default browser from WSL (written by noeda-setup).
[ $# -gt 0 ] || { echo "usage: windows-browser URL" >&2; exit 2; }
for url in "$@"; do
    /mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler "$url" >/dev/null 2>&1 &
done
exit 0
OPENER
chmod +x "$HOME/.local/bin/windows-browser"
cat > "$HOME/.local/share/applications/windows-browser.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Windows default browser (from WSL)
Exec=$HOME/.local/bin/windows-browser %u
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
NoDisplay=true
DESKTOP

# Default browser for links from Linux apps (xdg-open, $BROWSER), per --browser.
xdg-mime default "$BROWSER_DESKTOP" x-scheme-handler/http x-scheme-handler/https text/html
mkdir -p "$(dirname "$BROWSER_PREF_FILE")"
printf '%s\n' "$BROWSER_CHOICE" > "$BROWSER_PREF_FILE"
info "links open in: $BROWSER_CHOICE (xdg-open https -> $(xdg-mime query default x-scheme-handler/https))"

# GUI apps started outside a shell (e.g. from the Windows Start menu) get these via systemd.
mkdir -p "$HOME/.config/environment.d"
rm -f "$HOME/.config/environment.d/ssh-agent.conf"   # name used by earlier versions of this script
printf 'SSH_AUTH_SOCK=%s/openssh_agent\nDONT_PROMPT_WSL_INSTALL=1\nBROWSER=%s\n' \
    "/run/user/$(id -u)" "$BROWSER_CMD" > "$HOME/.config/environment.d/noeda.conf"
export SSH_AUTH_SOCK="/run/user/$(id -u)/openssh_agent"
export BROWSER="$BROWSER_CMD"

# ---------------------------------------------------------------- git identity
step "Git"
# The Windows Git Credential Manager is gone with appendWindowsPath=false / Git for Windows.
if git config --global --get credential.helper 2>/dev/null | grep -qi 'git-credential-manager\.exe'; then
    git config --global --unset-all credential.helper
    info "removed old Windows Git Credential Manager helper"
fi
git config --global init.defaultBranch main
if [ -z "$(git config --global user.name || true)" ]; then
    read -r -p "  Your name for Git commits: " gname
    git config --global user.name "$gname"
fi
if [ -z "$(git config --global user.email || true)" ]; then
    read -r -p "  Your email for Git commits: " gemail
    git config --global user.email "$gemail"
fi
info "author: $(git config --global user.name) <$(git config --global user.email)>"

# ---------------------------------------------------------------- ssh
step "SSH key and agent"
systemctl --user enable --now ssh-agent.socket >/dev/null 2>&1 || warn "could not enable ssh-agent.socket"
[ -S "$SSH_AUTH_SOCK" ] && info "agent socket: $SSH_AUTH_SOCK" || warn "agent socket not found at $SSH_AUTH_SOCK"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    info "creating an SSH key for GitHub. Choose a passphrase (recommended)."
    ssh-keygen -t ed25519 -C "$(git config --global user.email) ($(hostname) WSL)" -f "$HOME/.ssh/id_ed25519"
fi
if ! grep -q '^Host github.com' "$HOME/.ssh/config" 2>/dev/null; then
    printf 'Host github.com\n  AddKeysToAgent yes\n  IdentityFile ~/.ssh/id_ed25519\n' >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    info "added github.com entry to ~/.ssh/config"
fi
# Without a working agent (warned above) or if the passphrase prompt fails, carry on: ssh still
# uses ~/.ssh/id_ed25519 directly via the IdentityFile entry, it just asks for the passphrase.
if ! ssh-add -l >/dev/null 2>&1; then
    ssh-add "$HOME/.ssh/id_ed25519" || warn "could not add the SSH key to an agent; Git will ask for its passphrase each time"
fi
touch "$HOME/.ssh/known_hosts"
ssh-keygen -F github.com >/dev/null || ssh-keyscan -t ed25519 github.com 2>/dev/null >> "$HOME/.ssh/known_hosts"

# ---------------------------------------------------------------- github
step "GitHub (gh)"
if ! gh auth status -h github.com >/dev/null 2>&1; then
    info "Sign in to GitHub. Open the URL shown, enter the code, and authorize."
    gh auth login -h github.com --git-protocol ssh --web --skip-ssh-key -s admin:public_key
else
    # Capture first: with pipefail, 'cmd | grep -q' can fail on SIGPIPE even when it matches.
    gh_status="$(gh auth status -h github.com 2>&1 || true)"
    case "$gh_status" in
        *admin:public_key*) ;;
        *) gh auth refresh -h github.com -s admin:public_key ;;
    esac
fi
gh auth setup-git -h github.com    # HTTPS remotes on the host use gh's token
PUB="$(awk '{print $2}' "$HOME/.ssh/id_ed25519.pub")"
keys="$(gh api user/keys --jq '.[].key' 2>/dev/null || true)"
case "$keys" in
    *"$PUB"*) info "SSH key already registered on GitHub" ;;
    *) gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname) WSL Ubuntu" \
           || warn "could not add the SSH key to GitHub (add it at https://github.com/settings/keys)" ;;
esac
ssh_out="$(ssh -T -o BatchMode=yes git@github.com 2>&1 || true)"   # ssh -T always exits 1 on GitHub
if printf '%s' "$ssh_out" | grep -q 'successfully authenticated'; then
    info "ssh git@github.com: OK"
else
    warn "ssh to GitHub did not authenticate yet (a new key can take a minute)"
fi

# ---------------------------------------------------------------- editors
step "Editors"
# WSLg has no desktop keyring by default; without this, VS Code/Cursor warn at every start.
for dir in "$HOME/.vscode" "$HOME/.cursor"; do
    mkdir -p "$dir"
    [ -f "$dir/argv.json" ] || printf '{\n  "password-store": "basic"\n}\n' > "$dir/argv.json"
done
code --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 \
    && info "VS Code: Dev Containers extension installed" || warn "VS Code extension install failed"
cursor_ext="$(cursor --list-extensions 2>/dev/null || true)"
case "$cursor_ext" in
    *remote-containers*) info "Cursor: Dev Containers support present" ;;
    *) cursor --install-extension anysphere.remote-containers >/dev/null 2>&1 \
           && info "Cursor: Dev Containers extension installed" || warn "Cursor extension install failed" ;;
esac

# ---------------------------------------------------------------- noe checkout
step "noe checkout ($NOE_DIR)"
if [ -d "$NOE_DIR/.git" ]; then
    if [ "$(git -C "$NOE_DIR" remote get-url origin)" != "$NOE_REPO_SSH" ]; then
        git -C "$NOE_DIR" remote set-url origin "$NOE_REPO_SSH"
        info "origin switched to SSH ($NOE_REPO_SSH)"
    fi
else
    mkdir -p "$(dirname "$NOE_DIR")"
    git clone "$NOE_REPO_SSH" "$NOE_DIR"
fi
git -C "$NOE_DIR" fetch --quiet origin && info "fetch over SSH: OK"

# ---------------------------------------------------------------- done
step "Done"
if [ "$NEEDS_WSL_RESTART" -eq 1 ]; then
    warn "Restart WSL to apply wsl.conf / docker group: in Windows PowerShell run  wsl --shutdown"
    info "then open Ubuntu again."
fi
cat <<EOF
  Next:
    cd $NOE_DIR
    code .        # or: cursor .
    Ctrl+Shift+P > Dev Containers: Reopen in Container
  Start the editor from this Ubuntu shell, so it inherits SSH_AUTH_SOCK.
EOF
