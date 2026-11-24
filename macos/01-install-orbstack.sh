#!/usr/bin/env bash
# Noeda developer workstation on macOS: an Ubuntu machine in OrbStack.     *** SKETCH: UNTESTED ***
#
# Same idea as 01-install-lima.sh, using OrbStack instead of Lima. OrbStack is faster to start
# and better integrated (file sharing, networking, 'ssh <machine>@orb' with no setup), but it is
# a commercial app: commercial use needs a paid licence. See docs/NOTES.md.
#
#   bash macos/01-install-orbstack.sh [--name noe] [-- <options for 02-setup-ubuntu.sh>]
#
# Needs: macOS 13+, Homebrew (or install OrbStack from orbstack.dev first). Safe to run again.
# Day to day:
#   orb start noe          # start the machine
#   orb stop noe           # stop it (or quit OrbStack, which stops all machines)
#   orb delete noe         # remove the machine and its disk
#
# Differences from the Lima route, to check on a real Mac:
#   - OrbStack machines share your Mac's files (/Users/... appears inside the machine) and this
#     cannot be switched off per machine. The VM is isolated from macOS less than with Lima.
#   - The machine user gets your macOS uid (usually 501). noe's container user is uid 1000, so
#     this script runs the setup as a separate machine user with uid 1000 ('dev' by default).
#   - OrbStack forwards the macOS ssh-agent into machines. 02-setup-ubuntu.sh uses the
#     machine's own systemd agent instead; check which one the editor's server sees
#     (echo $SSH_AUTH_SOCK in a Remote-SSH terminal) before trusting Git in the container.
#   - Docker Engine runs inside the machine (installed by 02-setup-ubuntu.sh), separate from
#     OrbStack's own macOS-wide Docker engine. Leave OrbStack's engine unused for noe.

set -euo pipefail

NAME="noe"
VM_USER="dev"
SETUP_ARGS=()
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../02-setup-ubuntu.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME="$2"; shift ;;
        --) shift; SETUP_ARGS=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option '$1' (options for the Ubuntu script go after --)" >&2; exit 2 ;;
    esac
    shift
done
case "$NAME" in colima|colima-*|orbstack|docker-desktop) echo "ERROR: pick another machine name" >&2; exit 2 ;; esac

step() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

step "Preflight"
[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS."
[ -f "$SETUP_SCRIPT" ] || die "02-setup-ubuntu.sh not found next to the macos/ folder."
info "macOS $(sw_vers -productVersion), $(uname -m)"

step "OrbStack"
if ! command -v orb >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || die "Install OrbStack from https://orbstack.dev (or install Homebrew), then run again."
    brew install --cask orbstack
    info "Open OrbStack once from Applications to finish its setup, then run this script again."
    exit 0
fi
orb status >/dev/null 2>&1 || orb start

step "Ubuntu machine ($NAME)"
if orb list 2>/dev/null | awk '{print $1}' | grep -qx "$NAME"; then
    info "machine exists"
else
    orb create ubuntu "$NAME"
fi
orb start "$NAME" >/dev/null 2>&1 || true

# A machine user with uid 1000 (see the header). Reuse one if it exists.
existing="$(orb -m "$NAME" getent passwd 1000 | cut -d: -f1 || true)"
if [ -n "$existing" ]; then
    VM_USER="$existing"
else
    orb -m "$NAME" sudo useradd -m -u 1000 -s /bin/bash -G sudo "$VM_USER"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$VM_USER" | orb -m "$NAME" sudo tee "/etc/sudoers.d/90-$VM_USER" >/dev/null
    info "created machine user '$VM_USER' (uid 1000, passwordless sudo like OrbStack's default user)"
fi

step "Set up Ubuntu inside the machine (02-setup-ubuntu.sh --headless)"
# OrbStack mounts /Users inside the machine, so the script can run from where it is.
orb -m "$NAME" -u "$VM_USER" bash "$SETUP_SCRIPT" --headless "${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}"

step "Editor"
# OrbStack adds its ssh config (~/.orbstack/ssh/config) to ~/.ssh/config itself.
ssh -o BatchMode=yes "$VM_USER@$NAME@orb" true && info "ssh $VM_USER@$NAME@orb: OK"
for ed in cursor code; do
    command -v "$ed" >/dev/null 2>&1 || continue
    case "$ed" in
        cursor) exts="anysphere.remote-ssh anysphere.remote-containers" ;;
        code)   exts="ms-vscode-remote.remote-ssh ms-vscode-remote.remote-containers" ;;
    esac
    for e in $exts; do "$ed" --install-extension "$e" >/dev/null 2>&1 || info "$ed: install $e by hand"; done
done

step "Done"
cat <<EOF
  In Cursor or VS Code: Remote-SSH: Connect to Host > $VM_USER@$NAME@orb
  Open the folder /home/$VM_USER/work/noe, then Cmd+Shift+P > Dev Containers: Reopen in Container.
  When you are done for the day:  orb stop $NAME
EOF
