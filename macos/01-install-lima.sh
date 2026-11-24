#!/usr/bin/env bash
# Noeda developer workstation on macOS: an Ubuntu VM with Lima.            *** SKETCH: UNTESTED ***
#
# The macOS counterpart of 01-install-wsl.ps1. Everything for noe (Docker Engine, Git, gh, the
# SSH key, the checkout) lives in one Ubuntu VM. macOS keeps only Lima and your editor, which
# connects to the VM with Remote-SSH. Stop the VM when you are done; delete it to remove nearly
# everything.
#
#   bash macos/01-install-lima.sh [--name noe] [--cpus N] [--memory GiB] [--disk GiB]
#                                 [-- <options for 02-setup-ubuntu.sh, e.g. --mirror de>]
#
# Needs: macOS 13+ (Apple's Virtualization.framework, 'vz'), Homebrew. Safe to run again.
# Day to day:
#   limactl start noe      # start the VM (a few seconds)
#   limactl stop noe       # stop it: frees its CPU and memory
#   limactl delete noe     # remove the VM and its disk (code, images, keys inside it)
#
# Why these VM settings (see docs/NOTES.md, "macOS and Linux hosts"):
#   - user.uid 1000: noe's container user 'vscode' is uid 1000. The checkout and the SSH agent
#     socket are bind-mounted into the container, so the VM user must have the same uid.
#     Lima's default is your macOS uid (usually 501), which would make both unwritable.
#   - no mounts: the VM cannot see your Mac's files (Lima mounts your home read-only by default).
#     The setup script is copied in instead.
#   - ssh.forwardAgent false: Git keys live in the VM's own ssh-agent, not in macOS.
#   - rosetta (Apple silicon): runs amd64 binaries in the arm64 VM, if an image needs it.
# Do not name the VM colima, orbstack or docker-desktop: noe's devcontainer scripts pick their
# Docker/SSH handling from the daemon's host name.

set -euo pipefail

NAME="noe"
CPUS=""
MEMORY="8"
DISK="100"
SETUP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../02-setup-ubuntu.sh"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
    case "$1" in
        --name)   NAME="$2"; shift ;;
        --cpus)   CPUS="$2"; shift ;;
        --memory) MEMORY="$2"; shift ;;
        --disk)   DISK="$2"; shift ;;
        --) shift; SETUP_ARGS=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option '$1' (options for the Ubuntu script go after --)" >&2; exit 2 ;;
    esac
    shift
done
case "$NAME" in colima|colima-*|orbstack|docker-desktop) echo "ERROR: pick another VM name" >&2; exit 2 ;; esac

step() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

step "Preflight"
[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS."
[ -f "$SETUP_SCRIPT" ] || die "02-setup-ubuntu.sh not found next to the macos/ folder."
command -v brew >/dev/null 2>&1 || die "Homebrew is needed to install Lima: https://brew.sh"
ARCH="$(uname -m)"   # arm64 (Apple silicon) or x86_64
if [ -z "$CPUS" ]; then
    CPUS=$(( $(sysctl -n hw.ncpu) / 2 )); [ "$CPUS" -ge 4 ] || CPUS=4
fi
info "macOS $(sw_vers -productVersion), $ARCH; VM '$NAME': $CPUS CPUs, ${MEMORY} GiB RAM, ${DISK} GiB disk"

step "Lima"
command -v limactl >/dev/null 2>&1 || brew install lima
info "$(limactl --version)"

step "Ubuntu VM ($NAME)"
if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$NAME"; then
    info "VM exists"
else
    ROSETTA=()
    [ "$ARCH" = "arm64" ] && ROSETTA=(--rosetta)
    limactl create --name "$NAME" --tty=false \
        --vm-type vz "${ROSETTA[@]+"${ROSETTA[@]}"}" \
        --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" \
        --set '.mounts = [] | .user.uid = 1000 | .ssh.forwardAgent = false' \
        template://ubuntu-lts
fi
[ "$(limactl list --format '{{.Status}}' "$NAME")" = "Running" ] || limactl start "$NAME"
VM_UID="$(limactl shell "$NAME" id -u)"
[ "$VM_UID" = "1000" ] || info "WARNING: VM user has uid $VM_UID, not 1000; Git and file writes in the dev container will fail."

step "Set up Ubuntu inside the VM (02-setup-ubuntu.sh --headless)"
limactl copy "$SETUP_SCRIPT" "$NAME:/tmp/02-setup-ubuntu.sh"
limactl shell --workdir / "$NAME" bash /tmp/02-setup-ubuntu.sh --headless "${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}"

step "SSH access for the editor"
# Lima writes ~/.lima/<name>/ssh.config with a 'Host lima-<name>' entry. Include it so the
# editor's Remote-SSH can connect. It must come before any Host block, so it goes at the top.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config"
INCLUDE_LINE="Include ~/.lima/*/ssh.config"
if ! grep -qxF "$INCLUDE_LINE" "$HOME/.ssh/config"; then
    cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak-noeda"
    { printf '%s\n\n' "$INCLUDE_LINE"; cat "$HOME/.ssh/config.bak-noeda"; } > "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    info "added '$INCLUDE_LINE' to ~/.ssh/config (backup: config.bak-noeda)"
fi
ssh -o BatchMode=yes "lima-$NAME" true && info "ssh lima-$NAME: OK"

step "Editor extensions (on macOS)"
if command -v cursor >/dev/null 2>&1; then
    cursor --install-extension anysphere.remote-ssh >/dev/null 2>&1 && info "Cursor: Remote-SSH" || info "Cursor: install Remote-SSH by hand"
    cursor --install-extension anysphere.remote-containers >/dev/null 2>&1 && info "Cursor: Dev Containers" || true
fi
if command -v code >/dev/null 2>&1; then
    code --install-extension ms-vscode-remote.remote-ssh >/dev/null 2>&1 && info "VS Code: Remote-SSH" || info "VS Code: install Remote-SSH by hand"
    code --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 && info "VS Code: Dev Containers" || true
fi
command -v cursor >/dev/null 2>&1 || command -v code >/dev/null 2>&1 \
    || info "No 'cursor' or 'code' command found. Install Cursor or VS Code on macOS (e.g. brew install --cask cursor)."

step "Done"
cat <<EOF
  In Cursor or VS Code: Remote-SSH: Connect to Host > lima-$NAME
  Open the folder ~/work/noe (in the VM), then Cmd+Shift+P > Dev Containers: Reopen in Container.
  When you are done for the day:  limactl stop $NAME
EOF
