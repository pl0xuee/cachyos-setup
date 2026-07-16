#!/usr/bin/env bash
#
# Post-install setup for a fresh CachyOS box.
#
# CachyOS ships a full desktop already, so this only installs the delta:
# the apps that aren't on the ISO, plus two programs of mine that aren't
# packaged anywhere and have to be built or fetched from GitHub.
#
# Everything here is idempotent — re-run it any time.
#
#   ./install.sh              # everything
#   ./install.sh --dry-run    # show what it would do, change nothing
#   ./install.sh --help       # options
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$REPO_DIR/packages"

# Where AgentTileCLI gets cloned. It has a built-in "check for updates" that
# pulls and rebuilds from its own clone, so this must be a permanent path you
# don't mind keeping — not a temp dir.
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/Projects}"

# StreamHub self-updates by overwriting its own AppImage in place, so it has to
# live somewhere your user can write. Anywhere root-owned (/opt, /usr/local/bin)
# would break that.
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
STREAMHUB_DIR="$HOME/.local/share/streamhub"
STREAMHUB_APPIMAGE="$BIN_DIR/StreamHub.AppImage"   # unversioned name is deliberate; see StreamHub's README
STREAMHUB_REPO="pl0xuee/StreamHub"
AGENTTILE_REPO="https://github.com/pl0xuee/agenttilecli.git"

# ConsoleVault is a Tauri app with the updater turned on, so like StreamHub it
# replaces its own AppImage in place — same reason it lives under ~/.local/bin.
# The release ships a versioned filename (ConsoleVault_x.y.z_amd64.AppImage); we
# install it under a stable name because Tauri's updater overwrites whatever path
# it's running from, and the .desktop launcher needs a filename that won't move.
CONSOLEVAULT_DIR="$HOME/.local/share/consolevault"
CONSOLEVAULT_APPIMAGE="$BIN_DIR/ConsoleVault.AppImage"
CONSOLEVAULT_REPO="pl0xuee/ConsoleVault"
# minisign public key, verbatim from the app's src-tauri/tauri.conf.json. It's
# hard-coded rather than fetched at runtime on purpose: pulling the key from the
# same GitHub release as the binary would "verify" a tampered download against a
# tampered key, which is no verification at all. Bump this only if the app rotates
# its signing key (and only from a source you trust, not the release page).
CONSOLEVAULT_PUBKEY="RWRWvWU0rorx3lM6O7xZd/SBN3UzFI5a/fPThO4FQVe3iad5QNfwVo2J"

# Disc Ripper is a PySide6/Qt AppImage that auto-rips DVDs/Blu-rays to H.265. Like
# the other two it's fetched from GitHub Releases under a stable filename and lives
# in ~/.local/bin. Unlike them the release publishes no signature or checksum asset
# — only the AppImage and its .zsync — so the download is verified against the
# full-file SHA-1 and length carried in that .zsync header. That's an integrity
# check, not a signature: the .zsync rides in the same release, so it catches a
# corrupt or truncated download, not a maliciously swapped release. It's the
# strongest check the release offers, and still beats running the binary unchecked.
DISCRIPPER_DIR="$HOME/.local/share/discripper"
DISCRIPPER_APPIMAGE="$BIN_DIR/DiscRipper.AppImage"
DISCRIPPER_REPO="pl0xuee/discripper"

# CPU power profile. power-profiles-daemon forgets this on reboot, so the config
# step also installs a user service that reapplies it at login.
POWER_PROFILE="performance"

# KDE's Power Management page (System Settings → Power Management).
#
# Only the "AC" profile is set: a desktop has no other one. On a laptop the
# Battery and Low Battery profiles are left at their defaults, which is what you
# want — never suspending on battery is a good way to find a flat machine.
SCREEN_OFF_MINS=10          # turn the screen off after this long idle
SCREEN_OFF_LOCKED_MINS=1    # ...and this long after the session locks

# Panel tweaks, taken from the real machine's plasma config rather than guessed.
# A stock CachyOS panel is otherwise identical, so these are the only deltas.

# Panel height in pixels. Plasma's default is 30. Note this lives in
# plasmashellrc, NOT the appletsrc where everything else about the panel is.
PANEL_HEIGHT=40

# Brave's homepage (the Home button), set via enterprise policy. Being policy,
# Brave marks it "managed by your organisation" and greys it out in Settings —
# to change it, edit this and re-run, or delete the policy file.
BRAVE_HOMEPAGE="https://pl0xuee.com"

# Brave filter lists to switch on, by UUID (brave://settings/shields/filters).
# These are NOT settable via enterprise policy — they live in Brave's own
# "Local State" file, so the script seeds them there instead.
BRAVE_FILTER_LISTS=(
    564C3B75-8731-404C-AD7C-5683258BA0B0    # Brave Experimental Adblock Rules
)

# Widgets to remove from the panel entirely.
PANEL_REMOVE=(
    org.kde.plasma.showdesktop      # "Peek at Desktop"
)

# System-tray items to tuck behind the expander arrow instead of showing inline.
TRAY_HIDDEN=(
    org.kde.plasma.brightness       # Brightness and Color
    org.kde.plasma.clipboard
    org.kde.plasma.battery
    org.kde.plasma.keyboardindicator
)

SKIP_UPGRADE=0
DRY_RUN=0
ONLY=""

# ── output ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
STEP_N=0
STEP_TOTAL=8     # preflight + 7 steps; recalculated below if --only is used

step() {
    STEP_N=$((STEP_N + 1))
    printf '\n%s┌─ %s[%d/%d]%s %s%s%s\n' \
        "$BLUE" "$DIM" "$STEP_N" "$STEP_TOTAL" "$RESET$BLUE" "$BOLD$*" "$RESET" ""
}
info() { printf '   %s\n' "$*"; }
ok()   { printf '   %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
skip() { printf '   %s·%s %s%s%s\n' "$DIM" "$RESET" "$DIM" "$*" "$RESET"; }
# Warnings are also collected and reprinted at the end. During a ten-minute run
# a warning at minute two has long scrolled off the screen by the time it
# matters, which is the same as never having printed it.
WARNINGS=()
warn() {
    WARNINGS+=("$*")
    printf '   %s▲%s %s\n' "$YELLOW" "$RESET" "$*" >&2
}
die()  { printf '\n %s✗ error:%s %s\n\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

BOX_W=52

# Draw a box around some lines. Built rather than hand-drawn: counting box
# characters by eye is how you end up with a border that's one column out.
box() {
    local colour="$1"; shift
    local line pad rule=""
    local i
    for (( i = 0; i < BOX_W; i++ )); do rule+="─"; done

    printf '\n%s╭%s╮%s\n' "$colour" "$rule" "$RESET"
    for line in "$@"; do
        # Width in characters, not bytes — the text may contain non-ASCII.
        pad=$(( BOX_W - 2 - ${#line} ))
        (( pad < 0 )) && pad=0
        printf '%s│%s  %s%*s%s│%s\n' "$colour" "$RESET" "$line" "$pad" "" "$colour" "$RESET"
    done
    printf '%s╰%s╯%s\n' "$colour" "$rule" "$RESET"
}

banner() {
    box "$BOLD$BLUE" \
        "CachyOS post-install setup" \
        "everything that isn't on the ISO"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Collected as the run goes, printed as a report at the end. Steps record what
# they actually did, not what they intended to do.
SUMMARY=()
report() { SUMMARY+=("$(printf '%-14s %s' "$1" "$2")"); }

# Every mutating command goes through this, so --dry-run is honest: if it isn't
# wrapped in run(), it doesn't change anything.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   %s[dry-run]%s %s\n' "$YELLOW" "$RESET" "$*"
    else
        "$@"
    fi
}

usage() {
    cat <<EOF
Post-install setup for a fresh CachyOS box.

Usage: ./install.sh [options]

Options:
  --dry-run       Print every command that would run, change nothing
  --only STEP     Run one step only:
                    packages | flatpak | agenttilecli | streamhub | consolevault | discripper | config
  --skip-upgrade  Don't run 'pacman -Syu' first (not recommended — see below)
  -h, --help      This message

Steps:
  config          Enables the LACT daemon and puts ~/.local/bin on PATH. Both
                  are needed for a working setup, so they run by default —
                  there is nothing to do by hand after this script.

Notes:
  A full system upgrade runs first by default. On Arch-based systems that
  isn't optional busywork: installing a new package against a stale package
  database is a partial upgrade, and partial upgrades break things. Skip it
  only if you just upgraded.

Env:
  PROJECTS_DIR    Where to clone AgentTileCLI (default: ~/Documents/Projects)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=1; shift ;;
        # Guard the arg count first: `shift 2` with only one argument left
        # returns non-zero, and set -e would then exit silently — no usage, no
        # error, nothing. `./install.sh --only` would just print nothing and fail.
        --only)         [[ $# -ge 2 ]] || die "--only needs a step (packages | flatpak | agenttilecli | streamhub | consolevault | discripper | config)"
                        ONLY="$2"; shift 2 ;;
        --skip-upgrade) SKIP_UPGRADE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown option: $1 (try --help)" ;;
    esac
done

if [[ -n "$ONLY" ]]; then
    case "$ONLY" in
        packages|flatpak|agenttilecli|streamhub|consolevault|discripper|config) ;;
        *) die "--only takes: packages | flatpak | agenttilecli | streamhub | consolevault | discripper | config" ;;
    esac
fi
wanted() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }
[[ -n "$ONLY" ]] && STEP_TOTAL=2      # preflight + the one requested step

# Strip inline #-comments, trailing whitespace and blank lines from a list file.
# Callers must check the file exists first — this runs inside a process
# substitution, where a die() here could not abort the parent shell.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# ── preflight ─────────────────────────────────────────────────────────────────
preflight() {
    step "Preflight"

    [[ $EUID -ne 0 ]] || die "don't run this as root — it installs into your home dir. It'll ask for sudo when it needs it."
    have pacman || die "no pacman — this script is for Arch/CachyOS."
    have curl   || die "curl is not installed."
    have sudo   || die "sudo is not installed."
    # Used to verify StreamHub's sha512 and to merge Brave's Local State JSON.
    # It's part of the CachyOS base install, so this should never fire — but a
    # missing python would otherwise surface as a confusing checksum failure.
    have python || die "python is not installed (needed for checksum + JSON handling)."

    for f in "$PKG_DIR/pacman.txt" "$PKG_DIR/flatpak.txt"; do
        [[ -f "$f" ]] || die "missing package list: $f"
    done

    curl -fsS --max-time 10 -o /dev/null https://archlinux.org 2>/dev/null \
        || die "no network (couldn't reach archlinux.org)."
    ok "root check, pacman, curl, sudo, package lists, network"

    if [[ $DRY_RUN -eq 1 ]]; then
        skip "dry run — no sudo needed, nothing will be changed"
        return
    fi

    # Grab sudo once up front so the script doesn't stall on a password prompt
    # 20 minutes in, then hold the timestamp open while the long builds run.
    #
    # Only prompt if sudo actually needs it. 'sudo -v' insists on a terminal
    # even when the user is NOPASSWD, which would make this script impossible to
    # run over SSH or from any non-interactive context — the -n probe first means
    # a passwordless or already-cached sudo sails straight through.
    if sudo -n true 2>/dev/null; then
        ok "sudo already available without a password"
    else
        info "Asking for sudo up front so nothing blocks later..."
        sudo -v || die "sudo failed (no terminal to prompt on? run this from a shell, or configure NOPASSWD)."
        ok "sudo cached"
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    SUDO_KEEPALIVE=$!
    trap cleanup EXIT
}

# Runs however the script ends, including a crash.
cleanup() {
    [[ -n "${SUDO_KEEPALIVE:-}" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null

    # The taskbar step stops plasmashell so it can't overwrite the config we're
    # writing. If anything failed in between, the user is staring at a desktop
    # with NO PANEL and no obvious way to get it back. Always put it back.
    if [[ "${PLASMA_STOPPED:-0}" -eq 1 ]] && ! pgrep -x plasmashell >/dev/null 2>&1; then
        printf '   %s!%s restoring plasmashell after an error...\n' "$YELLOW" "$RESET" >&2
        systemctl --user start plasma-plasmashell.service 2>/dev/null \
            || { setsid plasmashell > /dev/null 2>&1 & }
    fi
    return 0
}

# ── 1. pacman packages ────────────────────────────────────────────────────────
install_packages() {
    step "Repo packages"

    if [[ $SKIP_UPGRADE -eq 1 ]]; then
        skip "system upgrade skipped (--skip-upgrade)"
    else
        info "Full system upgrade (avoids a partial-upgrade break)..."
        run sudo pacman -Syu --noconfirm
    fi

    local pkgs=()
    mapfile -t pkgs < <(read_list "$PKG_DIR/pacman.txt")
    [[ ${#pkgs[@]} -gt 0 ]] || { skip "no packages listed"; return; }

    # --needed makes this a no-op for anything already present, so most of
    # these get skipped on a CachyOS box that already ships them.
    info "Installing ${#pkgs[@]} packages (already-present ones are skipped)..."

    if [[ $DRY_RUN -eq 1 ]]; then
        run sudo pacman -S --needed --noconfirm "${pkgs[@]}"
        return
    fi

    # Diff the installed set around the transaction rather than parsing pacman's
    # output — that way the report says what actually landed, including the
    # dependencies pulled in behind the packages we asked for.
    local before after
    before="$(pacman -Qq | sort)"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    after="$(pacman -Qq | sort)"

    local new_all=() new_wanted=()
    mapfile -t new_all < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))

    local p
    for p in "${pkgs[@]}"; do
        printf '%s\n' "${new_all[@]}" | grep -qx "$p" && new_wanted+=("$p")
    done

    ok "repo packages installed"

    if [[ ${#new_all[@]} -eq 0 ]]; then
        report "Packages" "all ${#pkgs[@]} already present — nothing to do"
    else
        local deps=$(( ${#new_all[@]} - ${#new_wanted[@]} ))
        report "Packages" "${#new_wanted[@]} of ${#pkgs[@]} newly installed, plus $deps dependencies"
        # NOT `[[ ... ]] && report ...`. As the last command of the function that
        # would return 1 whenever new_wanted is empty (packages upgraded rather
        # than newly installed, say), and `set -e` would then kill the whole run
        # right here — no flatpaks, no apps, no config, no summary, no message.
        if [[ ${#new_wanted[@]} -gt 0 ]]; then
            report "" "${new_wanted[*]}"
        fi
    fi
    return 0
}

# ── 2. flatpaks ───────────────────────────────────────────────────────────────
install_flatpaks() {
    step "Flatpaks"

    # flatpak is NOT on a stock CachyOS install, so pacman.txt installs it. If
    # it's missing here, the package step was skipped (--only flatpak) rather
    # than anything being broken.
    have flatpak || die "flatpak is not installed — run the packages step first (it's in packages/pacman.txt)."

    local apps_dry=()
    if [[ $DRY_RUN -eq 1 ]]; then
        # Even read-only flatpak queries ('remotes', 'info') scaffold
        # ~/.local/share/flatpak and ~/.cache/flatpak on first use. That's a
        # filesystem change, and a dry run promises not to make any — so in dry
        # mode we don't invoke flatpak at all, we just say what we'd do.
        run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        mapfile -t apps_dry < <(read_list "$PKG_DIR/flatpak.txt")
        local a
        for a in "${apps_dry[@]}"; do
            run sudo flatpak install -y --noninteractive flathub "$a"
        done
        return
    fi

    # --system, not the default (which lists user AND system remotes). We install
    # system-wide, so a Flathub remote that exists only in the *user* scope — as
    # Discover tends to add it — would satisfy an unscoped check while the system
    # install still fails with "Remote 'flathub' not found".
    #
    # remote-add --if-not-exists is idempotent anyway; the check is only here so
    # a re-run can say "already configured" instead of silently doing nothing.
    if flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
        skip "Flathub remote already configured"
    else
        info "Adding Flathub remote..."
        run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    local apps=()
    mapfile -t apps < <(read_list "$PKG_DIR/flatpak.txt")
    [[ ${#apps[@]} -gt 0 ]] || { skip "no flatpaks listed"; return; }

    local app installed=() already=()
    for app in "${apps[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            skip "$app (already installed)"
            already+=("$app")
        else
            info "Installing $app..."
            installed+=("$app")
            # As root, deliberately. A system-scope install is a privileged
            # operation that flatpak routes through polkit, and polkit needs an
            # interactive agent — so an unprivileged 'flatpak install' dies with
            # "Deploy not allowed for user" over SSH, and pops an auth dialog
            # mid-run on a desktop. sudo sidesteps both.
            run sudo flatpak install -y --noninteractive flathub "$app"
            ok "$app"
        fi
    done

    if [[ ${#installed[@]} -gt 0 ]]; then
        report "Flatpaks" "installed ${installed[*]}"
    else
        report "Flatpaks" "already present (${already[*]})"
    fi
}

# ── 3. AgentTileCLI (build from source) ───────────────────────────────────────
# Rust + GTK4/VTE4. Its own install.sh builds the release binary and drops a
# .desktop file + icon into ~/.local. We clone to a permanent path because the
# app's "check for updates" pulls and rebuilds from this same clone.
install_agenttilecli() {
    step "AgentTileCLI"

    ensure_claude_cli

    local dir="$PROJECTS_DIR/agenttilecli"
    run mkdir -p "$PROJECTS_DIR"

    if [[ -d "$dir/.git" ]]; then
        info "Clone exists — pulling latest..."
        # Fast-forward only. Local commits, a dev branch or uncommitted work
        # make this refuse rather than clobber anything.
        if ! run git -C "$dir" pull --ff-only; then
            warn "couldn't fast-forward $dir (local changes or a dev branch?) — building what's already there"
        fi
    else
        info "Cloning into $dir..."
        run git clone "$AGENTTILE_REPO" "$dir"
    fi

    info "Building (cargo release build — takes a few minutes)..."
    # Its install.sh checks for cargo/gtk4/vte4 itself and reports what's missing.
    #
    # stdin from /dev/null on purpose. That script offers to install the `claude`
    # CLI when it's absent, and only prompts if stdin is a terminal — so it sails
    # through a piped/SSH run but BLOCKS FOREVER when a human runs this from a
    # real shell, which is the normal case. ensure_claude_cli above means the
    # prompt shouldn't fire at all; </dev/null guarantees that neither it nor any
    # prompt it grows later can ever hang an unattended install.
    if [[ $DRY_RUN -eq 1 ]]; then
        run "(cd $dir && ./install.sh)"
    else
        ( cd "$dir" && ./install.sh < /dev/null )
    fi
    ok "AgentTileCLI installed to $BIN_DIR/agenttilecli"

    local commit="unknown"
    [[ $DRY_RUN -eq 0 ]] && commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    report "AgentTileCLI" "built from source ($commit) → $BIN_DIR/agenttilecli"
    report "" "clone kept at $dir (its updater rebuilds from here)"
}

# Find the applet id declaring a given plugin inside a containment.
#
# Uses index() rather than a regex: the group headers are full of [ ] and awk -v
# runs its OWN escape processing over -v values, so a "\[" written here arrives
# at awk as a bare "[" and the regex blows up as an unbalanced bracket. Plain
# string matching sidesteps the whole problem.
applet_id_for() {
    local conf="$1" cont="$2" plugin="$3"
    awk -v pfx="[Containments][$cont][Applets][" -v want="plugin=$plugin" '
        /^\[/ {
            a = ""
            if (index($0, pfx) == 1) {
                rest = substr($0, length(pfx) + 1)
                # Only a direct applet group, e.g. "[...][Applets][39]" — not a
                # sub-group like "[...][Applets][39][Configuration]".
                if (rest ~ /^[0-9]+\]$/) { sub(/\]$/, "", rest); a = rest }
            }
            next
        }
        a != "" && $0 == want { print a; exit }
    ' "$conf"
}

# Delete the widgets in PANEL_REMOVE from the panel.
#
# An applet lives in a group plus any number of sub-groups, and its id is also
# listed in the containment's AppletOrder — leave the id in AppletOrder after
# deleting the group and Plasma logs an error and can drop the panel. Both have
# to go.
panel_remove_widgets() {
    local conf="$1" cont="$2"
    [[ ${#PANEL_REMOVE[@]} -gt 0 ]] || return 0

    local plug id order removed=()
    for plug in "${PANEL_REMOVE[@]}"; do
        id="$(applet_id_for "$conf" "$cont" "$plug")"
        [[ -n "$id" ]] || continue

        # Rewrite AppletOrder FIRST, then delete the group.
        #
        # Order matters: an id left in AppletOrder whose group no longer exists is
        # the state that makes Plasma log an error and drop the panel. If we die
        # between the two operations, better to have an unused id still listed
        # (harmless — Plasma ignores it) than a dangling reference.
        order="$(kreadconfig6 --file "$conf" --group Containments --group "$cont" \
                    --group General --key AppletOrder 2>/dev/null || true)"
        if [[ -n "$order" ]]; then
            # `|| true`: grep -v exits 1 when it filters out EVERY line, which
            # happens when this applet is the only one in the list. Under pipefail
            # that would kill the script mid-surgery.
            order="$(tr ';' '\n' <<<"$order" | grep -vx "$id" | paste -sd';' - || true)"
            kwriteconfig6 --file "$conf" --group Containments --group "$cont" \
                --group General --key AppletOrder "$order"
        fi

        # Now drop the applet's group and every sub-group of it.
        #
        # mktemp INSIDE the config's own directory, not /tmp: /tmp is tmpfs and
        # $HOME is btrfs here, so `mv` across them is a copy+unlink rather than an
        # atomic rename(2) — an interrupt mid-copy would leave the Plasma config
        # truncated, at the exact moment plasmashell is stopped and can't help.
        # Same-filesystem mv is atomic. chmod --reference keeps the original 644
        # rather than mktemp's 600.
        local tmp
        tmp="$(mktemp "$conf.XXXXXX")" || { warn "couldn't create a temp file — skipping widget removal"; return 0; }
        if awk -v pfx="[Containments][$cont][Applets][$id]" '
                /^\[/ { skip = (index($0, pfx) == 1) }
                !skip
            ' "$conf" > "$tmp"
        then
            chmod --reference="$conf" "$tmp" 2>/dev/null || true
            mv -f "$tmp" "$conf"
            removed+=("$plug")
        else
            rm -f "$tmp"
            warn "couldn't rewrite the Plasma config — left $plug in place"
        fi
    done

    [[ ${#removed[@]} -gt 0 ]] && ok "removed from panel: ${removed[*]##*.}"
    return 0
}

# Tuck TRAY_HIDDEN items behind the system tray's expander arrow.
tray_hide_items() {
    local conf="$1" cont="$2"
    [[ ${#TRAY_HIDDEN[@]} -gt 0 ]] || return 0

    # The system tray is itself an applet of the panel.
    local tray
    tray="$(applet_id_for "$conf" "$cont" org.kde.plasma.systemtray)"
    [[ -n "$tray" ]] || { warn "no system tray applet found — not hiding tray items"; return 0; }

    local hidden
    hidden="$(IFS=,; echo "${TRAY_HIDDEN[*]}")"

    # Note the group is [...][Applets][N][General], NOT [Configuration][General]
    # like most applets — the system tray is a containment in its own right.
    kwriteconfig6 --file "$conf" \
        --group Containments --group "$cont" \
        --group Applets --group "$tray" \
        --group General \
        --key hiddenItems "$hidden"

    ok "hidden in system tray: ${TRAY_HIDDEN[*]##*.}"
    return 0
}

# AgentTileCLI launches `claude` in every pane, so without it the app opens to a
# grid of "command not found". Install it up front rather than letting
# AgentTileCLI's own installer stop and ask.
ensure_claude_cli() {
    if have claude; then
        skip "claude CLI already installed"
        return
    fi

    info "Installing the claude CLI (AgentTileCLI runs it in every pane)..."
    if [[ $DRY_RUN -eq 1 ]]; then
        run "curl -fsSL https://claude.ai/install.sh | bash"
        return
    fi

    if curl -fsSL https://claude.ai/install.sh | bash; then
        # It installs to ~/.local/bin, which isn't on PATH yet this early in the
        # run — export it so the AgentTileCLI installer's own `have claude` check
        # finds it and stays quiet.
        export PATH="$BIN_DIR:$PATH"
        ok "claude CLI installed"
    else
        warn "claude CLI install failed — AgentTileCLI's panes won't work until you run:"
        warn "    curl -fsSL https://claude.ai/install.sh | bash"
    fi
}

# ── 4. StreamHub (prebuilt AppImage) ──────────────────────────────────────────
# Fetched from GitHub Releases rather than built: the release AppImage bundles
# castLabs Electron (Widevine), which is what makes Netflix/Prime actually play.
# The app updates itself in place afterwards, so this normally runs once — but
# it's version-stamped, so a re-run still picks up a newer release if there is one.
install_streamhub() {
    step "StreamHub"

    local stamp="$STREAMHUB_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(curl -fsSL "https://api.github.com/repos/$STREAMHUB_REPO/releases/latest")" \
        || die "couldn't reach the GitHub releases API."
    # `|| true` is load-bearing. grep exits 1 when it matches nothing, pipefail
    # propagates that to the assignment, and set -e then kills the script BEFORE
    # the checks below can run — so a renamed or pulled asset would exit 1 with
    # no diagnostic at all, instead of the clear message we wrote for exactly
    # that case.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/StreamHub\.AppImage' | head -1 || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no StreamHub.AppImage asset in release $tag."

    if [[ -f "$STREAMHUB_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "StreamHub $tag already installed (it self-updates from here on)"

        # Don't just return — repair the launcher if it's gone. Otherwise deleting
        # the .desktop file (or having the icon fetch fail on an earlier run)
        # leaves you permanently unable to get it back: the version stamp still
        # matches, so every future run skips straight past this.
        if [[ ! -f "$APPS_DIR/com.streamhub.app.desktop" || ! -f "$STREAMHUB_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$STREAMHUB_DIR"
            [[ -f "$STREAMHUB_DIR/icon.png" ]] || curl -fsSL -o "$STREAMHUB_DIR/icon.png" \
                "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png" \
                || warn "couldn't fetch the icon"
            write_streamhub_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        report "StreamHub" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$STREAMHUB_DIR" "$APPS_DIR"

    info "Downloading StreamHub $tag..."
    # Download to a temp file beside the target, then move into place, so an
    # interrupted download can't leave a half-written AppImage that still looks
    # runnable — and so a failed update can't destroy a working install.
    local tmp="$STREAMHUB_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha512 against the release's latest-linux.yml"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$STREAMHUB_APPIMAGE"
        run curl -fsSL -o "$STREAMHUB_DIR/icon.png" "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png"
        run "write $APPS_DIR/com.streamhub.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable.
        #
        # This is a 130MB binary fetched off the internet and then run with your
        # user's full privileges. electron-builder publishes a sha512 for it in
        # latest-linux.yml alongside the release, so there is no good reason to
        # take the download on trust. A mismatch means a corrupt download or a
        # tampered asset; either way we stop rather than chmod +x it.
        verify_streamhub "$tmp" "$tag" || { rm -f "$tmp"; die "StreamHub download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$STREAMHUB_APPIMAGE"

        curl -fsSL -o "$STREAMHUB_DIR/icon.png" \
            "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_streamhub_desktop
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "StreamHub $tag installed to $STREAMHUB_APPIMAGE"
    report "StreamHub" "$tag (prebuilt AppImage) → $STREAMHUB_APPIMAGE"
}

# Check the downloaded AppImage against the sha512 the release publishes in
# latest-linux.yml. Returns non-zero if it doesn't match, or if the checksum
# can't be fetched at all — "couldn't verify" is not the same as "verified", and
# is not a good enough reason to run the binary anyway.
verify_streamhub() {
    local file="$1" tag="$2"
    local yml expected

    yml="$(curl -fsSL "https://github.com/$STREAMHUB_REPO/releases/download/$tag/latest-linux.yml" 2>/dev/null)" \
        || { warn "couldn't fetch latest-linux.yml — cannot verify the download"; return 1; }

    # The sha512 is base64, not hex, which is what electron-builder emits.
    expected="$(grep -m1 '^sha512:' <<<"$yml" | awk '{print $2}')"
    [[ -n "$expected" ]] || { warn "no sha512 in latest-linux.yml"; return 1; }

    local actual
    actual="$(python - "$file" <<'PY'
import base64, hashlib, sys
h = hashlib.sha512()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
print(base64.b64encode(h.digest()).decode())
PY
)" || { warn "couldn't compute the checksum"; return 1; }

    if [[ "$actual" == "$expected" ]]; then
        ok "checksum verified (sha512)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the published sha512"
    warn "  expected: $expected"
    warn "  got:      $actual"
    return 1
}

# Icon is referenced by absolute path rather than a themed name, which sidesteps
# having to guess which hicolor size directory the source PNG belongs in.
write_streamhub_desktop() {
    cat > "$APPS_DIR/com.streamhub.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=StreamHub
Comment=Netflix, Prime Video, Disney+, Max, Hulu and YouTube in one app
Exec=$STREAMHUB_APPIMAGE
Icon=$STREAMHUB_DIR/icon.png
Terminal=false
Categories=AudioVideo;Video;Player;
StartupNotify=true
StartupWMClass=StreamHub
EOF
}

# KDE keeps its own application-menu index; without kbuildsycoca a new .desktop
# file may not appear in the menu or KRunner until the next login.
refresh_desktop_db() {
    have update-desktop-database && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    have kbuildsycoca6           && kbuildsycoca6 >/dev/null 2>&1 || true
    return 0
}

# ── 5. ConsoleVault (prebuilt AppImage) ───────────────────────────────────────
# A Tauri launcher for a physical ROM collection (SNES/N64/PS1/PS2/PS3). Like
# StreamHub it's a self-updating AppImage fetched from GitHub Releases, so this
# normally runs once but is version-stamped to pick up a newer release on re-run.
install_consolevault() {
    step "ConsoleVault"

    local stamp="$CONSOLEVAULT_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(curl -fsSL "https://api.github.com/repos/$CONSOLEVAULT_REPO/releases/latest")" \
        || die "couldn't reach the GitHub releases API."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before we can print the clear message below — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The trailing `"` in the pattern is what keeps this from also matching the
    # sibling `..._amd64.AppImage.sig` asset URL.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no ConsoleVault _amd64.AppImage asset in release $tag."

    if [[ -f "$CONSOLEVAULT_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "ConsoleVault $tag already installed (it self-updates from here on)"

        # Same launcher-repair logic as StreamHub: a matching version stamp would
        # otherwise skip this step forever, stranding a deleted .desktop/icon.
        if [[ ! -f "$APPS_DIR/com.consolevault.app.desktop" || ! -f "$CONSOLEVAULT_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$CONSOLEVAULT_DIR"
            [[ -f "$CONSOLEVAULT_DIR/icon.png" ]] || curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" \
                "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png" \
                || warn "couldn't fetch the icon"
            write_consolevault_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        report "ConsoleVault" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$CONSOLEVAULT_DIR" "$APPS_DIR"

    info "Downloading ConsoleVault $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download or a failed update never leaves a half-written or
    # unverified AppImage where a runnable one used to be.
    local tmp="$CONSOLEVAULT_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify minisign signature against the embedded public key"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$CONSOLEVAULT_APPIMAGE"
        run curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png"
        run "write $APPS_DIR/com.consolevault.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable. This is an 80MB binary pulled off
        # the internet and then run with your user's full privileges. Tauri signs
        # every release with minisign and embeds the matching public key in the
        # app source, so there's no reason to trust the download blind. A bad
        # signature means a corrupt or tampered asset — we stop, we don't chmod it.
        verify_consolevault "$tmp" "$url" || { rm -f "$tmp"; die "ConsoleVault download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$CONSOLEVAULT_APPIMAGE"

        curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" \
            "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_consolevault_desktop
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "ConsoleVault $tag installed to $CONSOLEVAULT_APPIMAGE"
    report "ConsoleVault" "$tag (prebuilt AppImage) → $CONSOLEVAULT_APPIMAGE"
}

# Verify the AppImage against the minisign signature the release publishes next to
# it (…AppImage.sig), using the public key baked into this script. Returns
# non-zero if the signature is missing, malformed, or doesn't match — "couldn't
# check" is treated exactly like "failed", never like "passed".
verify_consolevault() {
    local file="$1" url="$2"

    # minisign isn't in the CachyOS base install. It's listed in packages/pacman.txt
    # so a normal run already has it, but `--only consolevault` can reach here
    # without the packages step, so pull it in on the fly rather than failing.
    if ! have minisign; then
        info "Installing minisign (needed to verify the download)..."
        run sudo pacman -S --needed --noconfirm minisign \
            || { warn "couldn't install minisign — cannot verify the download"; return 1; }
    fi

    # Tauri publishes the .sig as base64 of the actual minisign signature file, so
    # it has to be decoded before minisign will read it.
    local sig="$file.minisig"
    curl -fsSL "$url.sig" 2>/dev/null | base64 -d > "$sig" 2>/dev/null \
        || { warn "couldn't fetch/decode the .sig — cannot verify the download"; rm -f "$sig"; return 1; }
    [[ -s "$sig" ]] || { warn "empty signature — cannot verify the download"; rm -f "$sig"; return 1; }

    # -P takes the public key string directly, so there's no temp keyfile to clean
    # up. minisign auto-detects the prehashed (Tauri) signature format.
    if minisign -Vm "$file" -x "$sig" -P "$CONSOLEVAULT_PUBKEY" >/dev/null 2>&1; then
        rm -f "$sig"
        ok "signature verified (minisign)"
        return 0
    fi

    rm -f "$sig"
    warn "SIGNATURE MISMATCH — the download does not match the published minisign signature"
    return 1
}

write_consolevault_desktop() {
    cat > "$APPS_DIR/com.consolevault.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ConsoleVault
Comment=Launcher for your own physical ROM collection (SNES, N64, PS1, PS2, PS3)
Exec=$CONSOLEVAULT_APPIMAGE
Icon=$CONSOLEVAULT_DIR/icon.png
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
StartupWMClass=ConsoleVault
EOF
}

# ── 6. Disc Ripper (prebuilt AppImage) ────────────────────────────────────────
# A PySide6/Qt app that auto-detects a disc, rips it to H.265 and names the output
# for Plex/Jellyfin. Same shape as StreamHub/ConsoleVault — a GitHub-Releases
# AppImage under a stable name — but its release ships no signature or checksum, so
# it's verified against the SHA-1/length in the sibling .zsync (integrity, not a
# signature; see the note by DISCRIPPER_* above). Version-stamped so a re-run picks
# up a newer release.
install_discripper() {
    step "Disc Ripper"

    local stamp="$DISCRIPPER_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(curl -fsSL "https://api.github.com/repos/$DISCRIPPER_REPO/releases/latest")" \
        || die "couldn't reach the GitHub releases API."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The trailing `"` keeps this from also matching the sibling ...AppImage.zsync
    # asset URL, whose value continues past `.AppImage` before its closing quote.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/DiscRipper\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no DiscRipper.AppImage asset in release $tag."

    if [[ -f "$DISCRIPPER_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "Disc Ripper $tag already installed"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/com.discripper.app.desktop" || ! -f "$DISCRIPPER_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$DISCRIPPER_DIR"
            [[ -f "$DISCRIPPER_DIR/icon.png" ]] || curl -fsSL -o "$DISCRIPPER_DIR/icon.png" \
                "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png" \
                || warn "couldn't fetch the icon"
            write_discripper_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        report "Disc Ripper" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$DISCRIPPER_DIR" "$APPS_DIR"

    info "Downloading Disc Ripper $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download never leaves a half-written AppImage where a runnable
    # one used to be.
    local tmp="$DISCRIPPER_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha1/length against the release's DiscRipper.AppImage.zsync"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$DISCRIPPER_APPIMAGE"
        run curl -fsSL -o "$DISCRIPPER_DIR/icon.png" "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png"
        run "write $APPS_DIR/com.discripper.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable. This is an 80MB binary pulled off the
        # internet and then run with your user's full privileges. The release has no
        # signature to check, but the .zsync header records the full file's SHA-1
        # and length; a mismatch means a corrupt or truncated download and we stop
        # rather than chmod it. (This does not defend against a swapped release —
        # the .zsync comes from the same one — only against a broken transfer.)
        verify_discripper "$tmp" "$tag" || { rm -f "$tmp"; die "Disc Ripper download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$DISCRIPPER_APPIMAGE"

        curl -fsSL -o "$DISCRIPPER_DIR/icon.png" \
            "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_discripper_desktop
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "Disc Ripper $tag installed to $DISCRIPPER_APPIMAGE"
    report "Disc Ripper" "$tag (prebuilt AppImage) → $DISCRIPPER_APPIMAGE"
}

# Verify the AppImage against the SHA-1 and length recorded in its sibling .zsync
# header (the release ships no .sig or checksum file). Returns non-zero if the
# .zsync can't be fetched or the digest doesn't match — "couldn't check" is treated
# as "failed", never as "passed".
verify_discripper() {
    local file="$1" tag="$2"
    local zsync="$file.zsync" header expected_sha expected_len actual_sha actual_len

    curl -fsSL -o "$zsync" \
        "https://github.com/$DISCRIPPER_REPO/releases/download/$tag/DiscRipper.AppImage.zsync" 2>/dev/null \
        || { warn "couldn't fetch the .zsync — cannot verify the download"; rm -f "$zsync"; return 1; }

    # The .zsync is plain-text header lines, then a blank line, then a binary block.
    # sed quits at that blank line so the binary is never fed into the field parse.
    header="$(sed '/^$/q' "$zsync")"
    rm -f "$zsync"

    expected_sha="$(printf '%s\n' "$header" | grep -m1 '^SHA-1:' | awk '{print $2}')"
    expected_len="$(printf '%s\n' "$header" | grep -m1 '^Length:' | awk '{print $2}')"
    [[ -n "$expected_sha" ]] || { warn "no SHA-1 in the .zsync header — cannot verify"; return 1; }

    actual_sha="$(sha1sum "$file" | awk '{print $1}')"
    actual_len="$(stat -c%s "$file")"

    if [[ "$actual_sha" == "$expected_sha" && "$actual_len" == "$expected_len" ]]; then
        ok "checksum verified (sha1, from .zsync)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the .zsync header"
    warn "  expected: $expected_sha ($expected_len bytes)"
    warn "  got:      $actual_sha ($actual_len bytes)"
    return 1
}

write_discripper_desktop() {
    cat > "$APPS_DIR/com.discripper.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Disc Ripper
Comment=Auto-rip DVDs/Blu-rays to H.265 with Plex/Jellyfin naming
Exec=$DISCRIPPER_APPIMAGE
Icon=$DISCRIPPER_DIR/icon.png
Terminal=false
Categories=AudioVideo;Video;
StartupNotify=true
StartupWMClass=discripper
EOF
}

# ── 7. system config ──────────────────────────────────────────────────────────
configure_system() {
    step "System config"

    # LACT is useless without its daemon — the GUI just reports that it can't
    # connect. Failure here is not fatal: on a machine with no AMD GPU (a VM,
    # say) the daemon legitimately won't start, and that shouldn't sink an
    # otherwise good run.
    if systemctl is-enabled lactd >/dev/null 2>&1; then
        skip "lactd already enabled"
        report "Services" "lactd already enabled"
    elif run sudo systemctl enable --now lactd; then
        ok "lactd enabled (LACT can now talk to the GPU)"
        report "Services" "lactd enabled and started"
    else
        warn "couldn't start lactd — expected if this machine has no AMD GPU"
        report "Services" "lactd FAILED to start (no AMD GPU?)"
    fi

    # A fresh CachyOS doesn't have ~/.local/bin on PATH, and both custom apps
    # install their binaries there — so without this, 'agenttilecli' isn't a
    # command, which looks like the install silently failed.
    ensure_path

    configure_power_profile
    configure_powerdevil
    configure_brave_extensions
    configure_keepassxc_browser
    configure_taskbar
}

# Auto-install Brave extensions via Chromium enterprise policy.
#
# Brave is a Chromium fork and reads managed policy from /etc/brave/policies —
# confirmed by the paths compiled into the brave-origin binary. Dropping a policy
# file there makes Brave fetch the listed extensions from the Chrome Web Store on
# first launch.
#
# installation_mode is "normal_installed", NOT "force_installed": both install
# automatically, but force_installed also makes the extension impossible to
# disable or remove, even by the machine's owner. That's a reasonable thing for a
# corporate fleet and an unreasonable thing to do to yourself.
configure_brave_extensions() {
    local list="$PKG_DIR/brave-extensions.txt"
    local policy_dir="/etc/brave/policies/managed"
    local policy="$policy_dir/extensions.json"

    [[ -f "$list" ]] || { skip "no brave-extensions.txt — skipping"; return; }

    local ids=()
    mapfile -t ids < <(read_list "$list")
    [[ ${#ids[@]} -gt 0 ]] || { skip "no Brave extensions listed"; return; }

    local json="" id
    for id in "${ids[@]}"; do
        json+="${json:+,}
        \"$id\": {
            \"installation_mode\": \"normal_installed\",
            \"update_url\": \"https://clients2.google.com/service/update2/crx\"
        }"
    done

    if [[ $DRY_RUN -eq 1 ]]; then
        run "sudo mkdir -p $policy_dir"
        run "sudo write $policy (${#ids[@]} extensions, homepage + new tab -> $BRAVE_HOMEPAGE)"
        report "Brave" "${#ids[@]} extensions, homepage $BRAVE_HOMEPAGE"
        return
    fi

    sudo mkdir -p "$policy_dir"

    # HomepageIsNewTabPage=false is required, not decorative: leave it true and
    # Brave ignores HomepageLocation entirely and the Home button opens the new
    # tab page instead. NewTabPageLocation then points new tabs at the same URL.
    sudo tee "$policy" > /dev/null <<EOF
{
    "HomepageLocation": "$BRAVE_HOMEPAGE",
    "HomepageIsNewTabPage": false,
    "NewTabPageLocation": "$BRAVE_HOMEPAGE",
    "ShowHomeButton": true,

    "ExtensionSettings": {$json
    }
}
EOF

    ok "${#ids[@]} Brave extensions set to auto-install on first launch"
    ok "Brave homepage and new tab set to $BRAVE_HOMEPAGE"
    report "Brave" "${#ids[@]} extensions; homepage + new tab -> $BRAVE_HOMEPAGE"

    configure_brave_filters
}

# Switch on Brave's optional ad-block filter lists.
#
# There is no enterprise policy for these — they're stored per-profile in Brave's
# "Local State" JSON, keyed by the filter list's UUID. So we seed the file
# directly. Brave merges what's already there on startup, so writing this before
# it has ever run is fine, and it also works on an existing profile.
configure_brave_filters() {
    [[ ${#BRAVE_FILTER_LISTS[@]} -gt 0 ]] || return 0

    local state_dir="$HOME/.config/BraveSoftware/Brave-Origin"
    local state="$state_dir/Local State"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "enable ${#BRAVE_FILTER_LISTS[@]} Brave filter list(s) in $state"
        return
    fi

    # Brave rewrites Local State when it exits, so anything we write under a
    # running Brave gets thrown away without a word.
    if pgrep -x brave >/dev/null 2>&1; then
        warn "Brave is running — close it and re-run '--only config', or it will overwrite this"
    fi

    mkdir -p "$state_dir"

    if BRAVE_STATE="$state" BRAVE_UUIDS="${BRAVE_FILTER_LISTS[*]}" python - <<'PY'
import json, os

path   = os.environ["BRAVE_STATE"]
uuids  = os.environ["BRAVE_UUIDS"].split()

# Merge into whatever is already there; on a fresh box the file won't exist yet
# and Brave will happily fill in the rest of its defaults around what we write.
try:
    with open(path) as f:
        state = json.load(f)
except (FileNotFoundError, ValueError):
    state = {}

filters = state.setdefault("brave", {}).setdefault("ad_block", {}).setdefault("regional_filters", {})
for u in uuids:
    filters.setdefault(u, {})["enabled"] = True

with open(path, "w") as f:
    json.dump(state, f, separators=(",", ":"))
PY
    then
        ok "enabled ${#BRAVE_FILTER_LISTS[@]} Brave filter list(s) (experimental ad block)"
        report "" "experimental ad-block filter list enabled"
    else
        warn "couldn't write Brave's Local State — enable the filter list by hand in brave://settings/shields/filters"
    fi
}

# Wire KeePassXC's browser integration up to Brave Origin.
#
# KeePassXC's "Brave" checkbox writes its native-messaging manifest to
# ~/.config/BraveSoftware/Brave-Browser/ — the path UPSTREAM Brave uses. Brave
# Origin is a different build and reads ~/.config/BraveSoftware/Brave-Origin/,
# so ticking that box achieves precisely nothing and the extension sits there
# unable to reach the database. The manifest has to be placed by hand; this does
# it, which is the whole reason this function exists.
configure_keepassxc_browser() {
    have keepassxc-proxy || { skip "keepassxc not installed — skipping browser integration"; return; }

    local nm_dir="$HOME/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts"
    local manifest="$nm_dir/org.keepassxc.keepassxc_browser.json"
    local ini="$HOME/.config/keepassxc/keepassxc.ini"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "write $manifest"
        run "kwriteconfig6 --file $ini --group Browser --key Enabled true"
        report "KeePassXC" "would wire browser integration to Brave Origin"
        return
    fi

    # KeePassXC rewrites its ini on exit, so a running instance would undo this.
    if pgrep -x keepassxc >/dev/null 2>&1; then
        warn "KeePassXC is running — close it and re-run '--only config', or it will overwrite this"
    fi

    mkdir -p "$nm_dir"
    cat > "$manifest" <<EOF
{
    "allowed_origins": [
        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/",
        "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
    ],
    "description": "KeePassXC integration with native messaging support",
    "name": "org.keepassxc.keepassxc_browser",
    "path": "$(command -v keepassxc-proxy)",
    "type": "stdio"
}
EOF

    # The manifest alone isn't enough — KeePassXC won't answer the proxy unless
    # browser integration is switched on in its own settings.
    mkdir -p "$(dirname "$ini")"
    kwriteconfig6 --file "$ini" --group Browser --key Enabled true

    ok "KeePassXC browser integration wired to Brave Origin"
    report "KeePassXC" "browser integration enabled + Brave Origin manifest installed"
    info "  You still need the KeePassXC-Browser extension in Brave itself."
}

# Set the CPU power profile.
#
# power-profiles-daemon does NOT remember the active profile across reboots — it
# comes up on its default ("balanced") every time. Setting it once here would
# last until the next boot and no longer, so we also install a user service that
# reapplies it at login.
configure_power_profile() {
    if ! have powerprofilesctl; then
        warn "powerprofilesctl not found — skipping power profile"
        report "Power" "SKIPPED (power-profiles-daemon not installed)"
        return
    fi

    # dbus-activatable, so it works unenabled — but then nothing reapplies the
    # profile after a reboot.
    #
    # The `|| warn` matters: the command after a final `||` is NOT exempt from
    # set -e, so a failing enable would kill the whole run here and skip every
    # step after it (Brave, KeePassXC, the taskbar). And it can legitimately
    # fail — tuned-ppd also provides powerprofilesctl, so the `have` check above
    # passes on a machine where this unit doesn't exist at all.
    if ! systemctl is-enabled power-profiles-daemon >/dev/null 2>&1; then
        run sudo systemctl enable --now power-profiles-daemon \
            || warn "couldn't enable power-profiles-daemon (using tuned-ppd instead?)"
    fi

    # Not every machine offers every profile: it depends on the CPU's scaling
    # driver. A VM typically has no 'performance' at all. Setting a profile that
    # doesn't exist is an error, so check before asking for it.
    if ! powerprofilesctl list 2>/dev/null | grep -q "$POWER_PROFILE"; then
        warn "'$POWER_PROFILE' profile isn't available on this machine (no scaling driver? a VM?)"
        warn "available: $(powerprofilesctl list 2>/dev/null | grep -oE '^\*?[[:space:]]*[a-z-]+:' | tr -d '*: ' | tr '\n' ' ')"
        report "Power" "SKIPPED ('$POWER_PROFILE' unavailable here)"
        return
    fi

    run powerprofilesctl set "$POWER_PROFILE"

    # Reapply at every login, since the daemon won't remember it.
    local unit_dir="$HOME/.config/systemd/user"
    local unit="$unit_dir/power-profile.service"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "write $unit (reapplies '$POWER_PROFILE' at login)"
        run "systemctl --user enable power-profile.service"
        report "Power" "would set '$POWER_PROFILE' and reapply at login"
        return
    fi

    mkdir -p "$unit_dir"
    cat > "$unit" <<EOF
[Unit]
Description=Set the power profile to $POWER_PROFILE
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=$(command -v powerprofilesctl) set $POWER_PROFILE

[Install]
WantedBy=graphical-session.target
EOF

    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable power-profile.service >/dev/null 2>&1; then
        ok "power profile set to '$POWER_PROFILE', and reapplied at each login"
        report "Power" "'$POWER_PROFILE' set, persists across reboots"
    else
        warn "set '$POWER_PROFILE' for this boot, but couldn't enable the login service"
        report "Power" "'$POWER_PROFILE' set (will reset on reboot)"
    fi
}

# Stop the desktop putting itself to sleep behind your back.
#
# Distinct from configure_power_profile above: that one is the CPU's governor
# (power-profiles-daemon), this is KDE's idle behaviour (powerdevil). The two are
# unrelated and live in different places, despite both being "power" in the UI.
#
# The settings, in KDE's own words:
#
#   Suspend session, when inactive:  Do nothing
#   Dim automatically:               Never
#   Turn off screen:                 after SCREEN_OFF_MINS
#     ...when locked:                after SCREEN_OFF_LOCKED_MINS
#
# A box that suspends mid-download, mid-build, or mid-stream is worse than
# useless, and a desktop isn't running off a battery — but blanking the screen is
# still worth having, since a static desktop left on for hours is how OLED panels
# acquire a permanent taskbar.
#
# Everything else on that page (power button shows the logout screen, no profile
# switching on idle) is already KDE's default, so it isn't written here: keys
# absent from powerdevilrc mean "the default", and pinning them would only create
# something to drift out of date the day KDE changes its mind.
configure_powerdevil() {
    local conf="$HOME/.config/powerdevilrc"

    if ! have kwriteconfig6; then
        warn "kwriteconfig6 not found — skipping the KDE power settings"
        report "Power (KDE)" "SKIPPED (kwriteconfig6 missing)"
        return
    fi

    local off=$(( SCREEN_OFF_MINS * 60 ))
    local off_locked=$(( SCREEN_OFF_LOCKED_MINS * 60 ))

    if [[ $DRY_RUN -eq 1 ]]; then
        run "kwriteconfig6 --file $conf [AC][SuspendAndShutdown] AutoSuspendAction=0"
        run "kwriteconfig6 --file $conf [AC][Display] no dimming, screen off after ${off}s (${off_locked}s locked)"
        report "Power (KDE)" "would never suspend; screen off after ${SCREEN_OFF_MINS}m"
        return
    fi

    # 0 is powerdevil's "do nothing" — the same value the GUI writes when you pick
    # it from the dropdown. There's no separate "idle suspend off" switch.
    kwriteconfig6 --file "$conf" --group AC --group SuspendAndShutdown \
        --key AutoSuspendAction 0

    # DimDisplayIdleTimeoutSec is dead while WhenIdle is false, but the KCM writes
    # -1 next to it regardless, and matching it keeps this file identical to a
    # hand-configured one. The `--` is load-bearing: without it kwriteconfig6
    # reads the -1 as a command-line option and exits 1, which under set -e takes
    # the whole run down with it.
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key DimDisplayWhenIdle --type bool false
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key DimDisplayIdleTimeoutSec -- -1

    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayWhenIdle --type bool true
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayIdleTimeoutSec "$off"
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayIdleTimeoutWhenLockedSec "$off_locked"

    # powerdevil reads its config once at startup, so a running session keeps the
    # old idle timers until told otherwise. Ask it to re-read them; if it isn't
    # running (no desktop session — an SSH run, say) there's nothing to tell, and
    # the file we just wrote is picked up at next login anyway.
    if have qdbus6; then
        qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement \
            org.kde.Solid.PowerManagement.reparseConfiguration >/dev/null 2>&1 || true
    else
        dbus-send --session --type=method_call --dest=org.kde.Solid.PowerManagement \
            /org/kde/Solid/PowerManagement \
            org.kde.Solid.PowerManagement.reparseConfiguration >/dev/null 2>&1 || true
    fi

    ok "never suspends, never dims; screen off after ${SCREEN_OFF_MINS}m (${SCREEN_OFF_LOCKED_MINS}m locked)"
    report "Power (KDE)" "no suspend, no dimming, screen off after ${SCREEN_OFF_MINS}m"
}

# Pin the taskbar launchers, in the order given in packages/taskbar.txt.
#
# Plasma keeps these in the Icons-only Task Manager applet's config. The applet
# and containment IDs are assigned at first login and differ per machine, so they
# have to be looked up rather than hardcoded.
configure_taskbar() {
    local conf="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local list="$PKG_DIR/taskbar.txt"

    [[ -f "$list" ]] || { skip "no taskbar.txt — leaving the taskbar alone"; return; }

    if ! have kwriteconfig6; then
        warn "kwriteconfig6 not found — skipping taskbar setup"
        report "Taskbar" "SKIPPED (kwriteconfig6 missing)"
        return
    fi

    # Written at first login to Plasma. If it doesn't exist the user has never
    # logged into the desktop, and there's no applet to configure yet.
    if [[ ! -f "$conf" ]]; then
        warn "Plasma config not found — log into the desktop once, then re-run with --only config"
        report "Taskbar" "SKIPPED (no Plasma session yet)"
        return
    fi

    local entries=()
    mapfile -t entries < <(read_list "$list")
    [[ ${#entries[@]} -gt 0 ]] || { skip "taskbar.txt is empty"; return; }

    # Rebuild KDE's application cache FIRST.
    #
    # Plasma resolves each launcher's icon and name through sycoca, an index
    # built at login. Everything this script installed landed after that, so
    # Plasma doesn't know those .desktop files exist and the tiles render as
    # blank generic-document icons.
    #
    # This MUST run inside the desktop session's environment. KDE hashes
    # XDG_DATA_DIRS into the cache's filename, and a shell that isn't the session
    # (an SSH login, say) has a subtly different value — even just missing
    # trailing slashes. Build it from there and you write a cache under a
    # different hash, leaving the session reading a stale one: the result is an
    # entirely empty application menu. systemd-run --user borrows the real
    # session environment, which is exactly what we need.
    if [[ $DRY_RUN -eq 0 ]] && have kbuildsycoca6; then
        have update-desktop-database && update-desktop-database "$APPS_DIR" 2>/dev/null || true
        if have systemd-run && systemd-run --user --wait --collect --quiet kbuildsycoca6 2>/dev/null; then
            :
        else
            kbuildsycoca6 2>/dev/null || true
        fi
    fi

    # Drop anything that isn't actually installed — a launcher pointing at a
    # missing .desktop shows up as a dead, blank tile.
    local present=() missing=() e
    for e in "${entries[@]}"; do
        if [[ -f "/usr/share/applications/$e" || -f "$APPS_DIR/$e" \
              || -f "/var/lib/flatpak/exports/share/applications/$e" ]]; then
            present+=("$e")
        else
            missing+=("$e")
        fi
    done
    [[ ${#missing[@]} -gt 0 ]] && warn "not installed, so not pinned: ${missing[*]}"
    [[ ${#present[@]} -gt 0 ]] || { warn "none of the taskbar apps are installed"; return; }

    # Find the Icons-only Task Manager applet. Its containment/applet IDs are
    # per-machine, so walk the ini for the group that declares the plugin.
    local group
    group="$(awk '/^\[/ { g=$0 } /^plugin=org\.kde\.plasma\.icontasks$/ { print g; exit }' "$conf")"
    if [[ -z "$group" ]]; then
        warn "couldn't find the taskbar applet in the Plasma config — skipping"
        report "Taskbar" "SKIPPED (no icontasks applet found)"
        return
    fi

    local cont applet
    cont="$(sed -E 's/\[Containments\]\[([0-9]+)\].*/\1/' <<<"$group")"
    applet="$(sed -E 's/.*\[Applets\]\[([0-9]+)\]/\1/' <<<"$group")"

    local launchers=""
    for e in "${present[@]}"; do
        launchers+="${launchers:+,}applications:$e"
    done

    info "Pinning ${#present[@]} launchers..."

    if [[ $DRY_RUN -eq 1 ]]; then
        run "kwriteconfig6 ... launchers=$launchers"
        report "Taskbar" "${#present[@]} launchers would be pinned"
        return
    fi

    # Order matters. plasmashell rewrites this file when it exits, so writing
    # while it's running means our change is overwritten seconds later by its
    # in-memory copy. Quit it first, write, then bring it back.
    local was_running=0
    if pgrep -x plasmashell >/dev/null 2>&1; then
        was_running=1
        PLASMA_STOPPED=1          # cleanup() restores it if we die from here on
        kquitapp6 plasmashell 2>/dev/null || true

        # kquitapp6 returns 0 for a *delivered* DBus message, not for a process
        # that actually exited — so its exit code says nothing. Wait for the
        # process to really go, and escalate if it won't. Writing the config
        # under a live plasmashell means it dumps its in-memory copy over our
        # changes the moment it next exits: launchers, height and tray settings
        # all silently reverted, while we cheerfully print "✓ taskbar pinned".
        local i
        for i in {1..20}; do
            pgrep -x plasmashell >/dev/null 2>&1 || break
            sleep 0.5
        done
        if pgrep -x plasmashell >/dev/null 2>&1; then
            warn "plasmashell ignored the quit request — killing it so it can't revert our changes"
            pkill -x plasmashell 2>/dev/null || true
            sleep 1
        fi
        if pgrep -x plasmashell >/dev/null 2>&1; then
            warn "can't stop plasmashell — skipping panel changes rather than have them silently reverted"
            report "Taskbar" "SKIPPED (plasmashell wouldn't stop)"
            PLASMA_STOPPED=0
            return 0
        fi
    fi

    kwriteconfig6 --file "$conf" \
        --group Containments --group "$cont" \
        --group Applets --group "$applet" \
        --group Configuration --group General \
        --key launchers "$launchers"

    # Safe to edit the file directly: plasmashell is stopped, so nothing is going
    # to write its in-memory copy over the top of us.
    panel_remove_widgets "$conf" "$cont"
    tray_hide_items "$conf" "$cont"

    # Panel height lives in plasmashellrc, keyed by the same containment id —
    # not in the appletsrc with the rest of the panel's configuration.
    kwriteconfig6 --file "$HOME/.config/plasmashellrc" \
        --group PlasmaViews --group "Panel $cont" --group Defaults \
        --key thickness "$PANEL_HEIGHT"
    ok "panel height set to ${PANEL_HEIGHT}px"

    if [[ $was_running -eq 0 ]]; then
        ok "taskbar pinned (applies at next login)"
        report "Taskbar" "${#present[@]} launchers pinned — takes effect at next login"
        return
    fi

    # Restart it through systemd, NOT by launching it directly.
    #
    # Plasma 6 runs plasmashell as a systemd user unit, so restarting the unit
    # hands it the session's real environment. Spawning it straight from this
    # shell hands it OUR environment instead — and if this script is being run
    # from anywhere but a terminal inside the session, that environment is subtly
    # wrong, which produces a plasmashell that cannot see a single installed
    # application. An empty menu and seven blank tiles.
    if ! systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
        setsid plasmashell > /dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    # Confirm it actually came back before disarming cleanup()'s safety net.
    # Clearing the flag on faith means that if plasmashell failed to start — say
    # `setsid plasmashell` from a shell with no Wayland display, where it dies
    # instantly — we'd print "✓ restarted", disarm the one thing that would have
    # rescued it, and leave the user staring at a desktop with no panel.
    local i
    for i in {1..20}; do
        pgrep -x plasmashell >/dev/null 2>&1 && break
        sleep 0.5
    done

    if pgrep -x plasmashell >/dev/null 2>&1; then
        PLASMA_STOPPED=0
        ok "taskbar pinned (plasmashell restarted)"
    else
        warn "plasmashell didn't come back — cleanup will try again on exit; log out and in if the panel is missing"
    fi
    report "Taskbar" "${#present[@]} launchers pinned, in order"
    return 0
}

ensure_path() {
    # Deliberately does NOT test "$PATH".
    #
    # ensure_claude_cli exports BIN_DIR onto this process's PATH earlier in the
    # run, so by the time we get here $PATH always contains it — and an early
    # return on that basis would skip persisting anything at all. The script would
    # report "already on PATH", and at the user's next login `agenttilecli` would
    # not be a command. Check what's written to disk, not what's in this shell.
    local done_any=0 shells=() already=()

    # fish_add_path silently refuses to add a directory that doesn't exist, so a
    # config-only run (before anything has installed a binary there) would fail
    # with no useful explanation. Make sure the directory is there first.
    run mkdir -p "$BIN_DIR"

    # fish is the CachyOS default. fish_add_path writes a universal variable, so
    # it persists across sessions and is idempotent — running it twice doesn't
    # duplicate the entry.
    #
    # Its exit code is NOT a success signal: it returns non-zero when it made no
    # change, which includes the "already present" case AND, empirically, some
    # runs that did add the path. So set it, then check the variable to see
    # whether it actually took.
    if have fish; then
        if [[ $DRY_RUN -eq 0 ]] && fish -c 'contains "'"$BIN_DIR"'" $fish_user_paths' 2>/dev/null; then
            already+=(fish)
            done_any=1
        else
            run fish -c 'fish_add_path -U "'"$BIN_DIR"'"' || true
            if [[ $DRY_RUN -eq 1 ]] || fish -c 'contains "'"$BIN_DIR"'" $fish_user_paths' 2>/dev/null; then
                ok "added to fish PATH"
                done_any=1
                shells+=(fish)
            else
                warn "fish_add_path didn't take — add $BIN_DIR to fish_user_paths by hand"
            fi
        fi
    fi

    # Cover bash/zsh too, in case the shell ever changes. Guarded on the line
    # already being there so a re-run doesn't keep appending to the rc file.
    local rc name
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        name="$(basename "$rc")"
        if grep -qF '.local/bin' "$rc"; then
            already+=("$name")
            done_any=1
            continue
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            run "append PATH export to $rc"
        else
            printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
        fi
        ok "added to $name"
        done_any=1
        shells+=("$name")
    done

    [[ ${#already[@]} -gt 0 ]] && skip "already on PATH for: ${already[*]}"

    if [[ ${#shells[@]} -gt 0 ]]; then
        info "Open a new shell (or 'exec fish') for this to take effect."
        report "PATH" "$BIN_DIR added for: ${shells[*]}"
    elif [[ $done_any -eq 1 ]]; then
        report "PATH" "$BIN_DIR already on PATH"
    else
        warn "couldn't add $BIN_DIR to PATH — add it to your shell config by hand"
        report "PATH" "FAILED — add $BIN_DIR by hand"
    fi
    return 0
}

# ── run ───────────────────────────────────────────────────────────────────────
main() {
    banner
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   %sDRY RUN%s — showing what would happen. Nothing will be changed.\n' \
            "$BOLD$YELLOW" "$RESET"
    fi

    preflight
    wanted packages     && install_packages
    wanted flatpak      && install_flatpaks
    wanted agenttilecli && install_agenttilecli
    wanted streamhub    && install_streamhub
    wanted consolevault && install_consolevault
    wanted discripper   && install_discripper
    wanted config       && configure_system

    if [[ $DRY_RUN -eq 1 ]]; then
        box "$BOLD$YELLOW" \
            "Dry run complete" \
            "Nothing was installed, changed or downloaded."
        printf '\n'
        return
    fi

    local mins=$((SECONDS / 60)) secs=$((SECONDS % 60))
    box "$BOLD$GREEN" \
        "✓ Done in ${mins}m ${secs}s" \
        "Nothing left to do by hand."

    if [[ ${#SUMMARY[@]} -gt 0 ]]; then
        printf '\n%s  What changed%s\n' "$BOLD" "$RESET"
        local line
        for line in "${SUMMARY[@]}"; do
            printf '    %s\n' "$line"
        done
    fi

    # A warning that scrolled past ten minutes ago is a warning nobody read.
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        printf '\n%s  Worth a look%s\n' "$BOLD$YELLOW" "$RESET"
        local w
        for w in "${WARNINGS[@]}"; do
            printf '    %s▲%s %s\n' "$YELLOW" "$RESET" "$w"
        done
    fi

    printf '\n%s  Run them%s\n' "$BOLD" "$RESET"
    printf '    %sagenttilecli%s          tiling terminal for AI CLI sessions\n' "$BOLD" "$RESET"
    printf '    %sStreamHub.AppImage%s    Netflix / Prime / Disney+ in one app\n' "$BOLD" "$RESET"
    printf '    %sConsoleVault.AppImage%s ROM-collection launcher (SNES → PS3)\n' "$BOLD" "$RESET"
    printf '    %sDiscRipper.AppImage%s   auto-rip DVDs/Blu-rays to H.265 (Plex/Jellyfin)\n' "$BOLD" "$RESET"
    printf '    %s(or find everything in the app menu)%s\n\n' "$DIM" "$RESET"
}

# Only auto-run when executed. Sourcing the script (as tests/run.sh does) just
# defines the functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
