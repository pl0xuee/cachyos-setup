#!/usr/bin/env bash
#
# One-liner entry point. On a fresh CachyOS box:
#
#   curl -fsSL https://raw.githubusercontent.com/pl0xuee/cachyos-setup/master/bootstrap.sh | bash
#
# It clones the repo and runs install.sh. It has to clone rather than just pipe
# install.sh into bash, because install.sh reads its package lists from
# packages/*.txt — piping the script alone would give you a script with nothing
# to install.
#
# Piping a script from the internet into bash means running whatever is at that
# URL, sight unseen. If you'd rather look first (you should):
#
#   git clone https://github.com/pl0xuee/cachyos-setup.git
#   cd cachyos-setup
#   less install.sh
#   ./install.sh --dry-run
#   ./install.sh
#
set -euo pipefail

REPO_URL="https://github.com/pl0xuee/cachyos-setup.git"
DEST="${SETUP_DIR:-$HOME/Documents/Projects/cachyos-setup}"

command -v git >/dev/null 2>&1 || {
    echo "error: git is required. Install it with: sudo pacman -S git" >&2
    exit 1
}

if [[ -d "$DEST/.git" ]]; then
    echo "Updating $DEST..."
    git -C "$DEST" pull --ff-only || echo "  (couldn't fast-forward — using what's there)"
else
    echo "Cloning into $DEST..."
    mkdir -p "$(dirname "$DEST")"
    git clone --quiet "$REPO_URL" "$DEST"
fi

chmod +x "$DEST/install.sh"

# When this script is itself being piped from curl, our stdin IS that pipe, and
# it's at EOF. Hand install.sh the real terminal instead, so sudo can prompt for
# a password and the run doesn't die at the first hurdle.
if [[ -e /dev/tty ]]; then
    exec "$DEST/install.sh" "$@" < /dev/tty
else
    exec "$DEST/install.sh" "$@"
fi
