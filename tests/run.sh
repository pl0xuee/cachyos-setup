#!/usr/bin/env bash
#
# Tests for install.sh. Runs entirely locally — installs nothing, needs no VM.
#
# Covers the parts that can actually be wrong without a fresh machine to try
# them on: argument handling, the package-list parser, the GitHub release-API
# parsing, the generated .desktop file, and that --dry-run really is inert.
#
#   ./tests/run.sh
#
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_ROOT/install.sh"

PASS=0; FAIL=0
GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

pass() { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
         [[ $# -gt 1 ]] && printf '      %sgot: %s%s\n' "$DIM" "$2" "$RESET"; }
group(){ printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }

check_eq() { # desc, expected, actual
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
check_contains() { # desc, needle, haystack
    if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "no '$2' in: $3"; fi
}

# Pull in the functions without running main().
# shellcheck source=../install.sh
source "$SCRIPT"
# install.sh runs under `set -euo pipefail`, and sourcing leaks all of that into
# this shell. Each part breaks the suite differently:
#   -e         aborts on the first deliberately-failing command
#   pipefail   makes `awk ... | grep -q ...` report failure even on a match,
#              because grep -q exits early and awk dies of SIGPIPE
#   -u         turns any unset variable in a test into a hard error
# Turn the lot off; the tests manage their own exit codes.
set +e +u +o pipefail

# ── argument handling ─────────────────────────────────────────────────────────
group "Argument handling"

out="$(bash "$SCRIPT" --help 2>&1)"; rc=$?
check_eq "--help exits 0" "0" "$rc"
check_contains "--help documents --dry-run" "--dry-run" "$out"

out="$(bash "$SCRIPT" --bogus 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "unknown option is rejected" || fail "unknown option is rejected" "exit $rc"
check_contains "unknown option names the culprit" "--bogus" "$out"

out="$(bash "$SCRIPT" --only nonsense 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--only rejects an invalid step" || fail "--only rejects an invalid step" "exit $rc"

# ── set -e footguns ───────────────────────────────────────────────────────────
group "set -e cannot silently kill the run"

# A function whose LAST command is `[[ cond ]] && something` returns 1 when the
# condition is false. Called as `wanted x && install_x`, that's the command after
# the final &&, which set -e does NOT exempt — so the script exits, silently,
# with no summary and every later step skipped. This actually happened.
if awk '/^install_packages\(\)/,/^}/' "$SCRIPT" | grep -qE '^\s*\[\[.*\]\] && report'; then
    fail "install_packages doesn't end on a bare [[ ]] && ..." \
         "returns 1 when nothing new was installed; set -e kills the whole run"
else
    pass "install_packages doesn't end on a bare [[ ]] && ..."
fi

# grep exits 1 on no-match; under pipefail that propagates to the assignment and
# set -e kills the script BEFORE the `|| die` on the next line can report it.
if awk '/^install_streamhub\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*StreamHub.*|| true'; then
    pass "StreamHub asset parsing survives a no-match (|| true)"
else
    fail "StreamHub asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

# `--only` with no value: `shift 2` fails, set -e exits, user sees nothing.
out="$(bash "$SCRIPT" --only 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--only with no value exits non-zero" || fail "--only with no value exits non-zero"
check_contains "--only with no value explains itself" "needs a step" "$out"

# ── package-list parser ───────────────────────────────────────────────────────
group "Package-list parser"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/list.txt" <<'EOF'
# a leading comment
alpha

beta      # trailing comment
   # indented comment
gamma
EOF

mapfile -t parsed < <(read_list "$tmp/list.txt")
check_eq "strips comments and blanks" "alpha beta gamma" "${parsed[*]}"
check_eq "yields exactly 3 entries" "3" "${#parsed[@]}"

# The real lists must not be empty and must not smuggle a '#' through.
mapfile -t real < <(read_list "$REPO_ROOT/packages/pacman.txt")
[[ ${#real[@]} -gt 0 ]] && pass "pacman.txt is non-empty (${#real[@]} packages)" \
                        || fail "pacman.txt is non-empty"
if printf '%s\n' "${real[@]}" | grep -q '#'; then
    fail "no '#' survives the parser"
else
    pass "no '#' survives the parser"
fi
# A stray space would silently become two bogus package names.
if printf '%s\n' "${real[@]}" | grep -q ' '; then
    fail "no package name contains a space"
else
    pass "no package name contains a space"
fi

mapfile -t fp < <(read_list "$REPO_ROOT/packages/flatpak.txt")
check_eq "flatpak.txt parses to the Dropbox app id" "com.dropbox.Client" "${fp[*]}"

# A stock CachyOS install has no flatpak binary — verified in a VM. If the
# flatpak.txt list is non-empty, pacman.txt MUST install flatpak, or the
# Flatpak step dies on a fresh machine. (It doesn't die here, on a box that
# already has it — which is exactly why this needs asserting.)
if [[ ${#fp[@]} -gt 0 ]]; then
    if printf '%s\n' "${real[@]}" | grep -qx flatpak; then
        pass "pacman.txt installs flatpak (flatpak.txt is non-empty)"
    else
        fail "pacman.txt installs flatpak" "flatpak.txt lists apps but flatpak isn't in pacman.txt"
    fi
fi

# ── every package actually resolves in an enabled repo ────────────────────────
group "Package names resolve (live pacman query)"

missing=()
for p in "${real[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "all ${#real[@]} packages found in enabled repos"
else
    fail "all packages resolve" "not found: ${missing[*]}"
fi

# ── taskbar list ──────────────────────────────────────────────────────────────
group "Taskbar launcher list"

mapfile -t tb < <(read_list "$REPO_ROOT/packages/taskbar.txt")
check_eq "taskbar.txt parses to 7 launchers" "7" "${#tb[@]}"

# Every entry must be a .desktop name — 'applications:' prefixes or bare app
# names silently produce a dead tile rather than an error.
bad=()
for e in "${tb[@]}"; do
    [[ "$e" == *.desktop ]] || bad+=("$e")
done
if [[ ${#bad[@]} -eq 0 ]]; then
    pass "every entry is a .desktop file name"
else
    fail "every entry is a .desktop file name" "not .desktop: ${bad[*]}"
fi

# The order IS the feature — assert it, so a careless edit that reshuffles the
# list gets caught rather than silently rearranging the taskbar.
check_eq "launchers are in the intended order" \
    "brave-origin.desktop vesktop.desktop steam.desktop org.keepassxc.KeePassXC.desktop org.kde.dolphin.desktop dev.agenttilecli.AgentTileCli.desktop com.streamhub.app.desktop" \
    "${tb[*]}"

# ── KDE power settings ────────────────────────────────────────────────────────
group "KDE power settings (powerdevil)"

if have kwriteconfig6; then
    pd_home="$tmp/pdhome"; mkdir -p "$pd_home/.config"
    ( HOME="$pd_home" DRY_RUN=0 configure_powerdevil ) >/dev/null 2>&1
    pd="$(cat "$pd_home/.config/powerdevilrc" 2>/dev/null || true)"

    # 0 is "do nothing". Any other value here means the machine suspends itself
    # mid-build, which is the whole thing this setting exists to prevent.
    check_contains "idle suspend is off"        "AutoSuspendAction=0"                  "$pd"
    check_contains "dimming is off"             "DimDisplayWhenIdle=false"             "$pd"
    check_contains "screen still turns off"     "TurnOffDisplayWhenIdle=true"          "$pd"
    check_contains "screen off after 10m"       "TurnOffDisplayIdleTimeoutSec=600"     "$pd"
    check_contains "screen off after 1m locked" "TurnOffDisplayIdleTimeoutWhenLockedSec=60" "$pd"

    # Written under [AC], not at the top level: a key in the wrong group is
    # silently ignored by powerdevil, so the file would look right and do nothing.
    if grep -q '^\[AC\]\[Display\]' "$pd_home/.config/powerdevilrc" 2>/dev/null; then
        pass "keys land in the [AC][Display] group"
    else
        fail "keys land in the [AC][Display] group" "$pd"
    fi

    # kwriteconfig6 parses a bare -1 as a command-line option and exits 1, which
    # under set -e would take the entire run down. The `--` is what stops it.
    if awk '/^configure_powerdevil\(\)/,/^}/' "$SCRIPT" | grep -q -- '--key DimDisplayIdleTimeoutSec -- -1'; then
        pass "the negative dim timeout is passed after --"
    else
        fail "the negative dim timeout is passed after --" \
             "a bare -1 makes kwriteconfig6 exit 1 and set -e kills the run"
    fi
else
    printf '  %s·%s kwriteconfig6 not installed — skipping\n' "$DIM" "$RESET"
fi

# ── nothing may block on stdin ────────────────────────────────────────────────
group "No step can hang waiting for input"

# AgentTileCLI's own install.sh prompts to install the `claude` CLI, but ONLY
# when stdin is a tty — so it passes silently over SSH and hangs forever when a
# human runs this from a real terminal. Every sub-script we shell out to must
# have stdin closed.
if grep -qF './install.sh < /dev/null' "$SCRIPT"; then
    pass "AgentTileCLI's installer is run with stdin closed"
else
    fail "AgentTileCLI's installer is run with stdin closed" \
         "it can prompt for the claude CLI and block a real terminal run"
fi

# pacman/flatpak must never stop to ask either.
if grep -qE 'pacman -S(yu)? .*--noconfirm' "$SCRIPT"; then
    pass "pacman runs with --noconfirm"
else
    fail "pacman runs with --noconfirm"
fi
if grep -qF 'flatpak install -y --noninteractive' "$SCRIPT"; then
    pass "flatpak runs non-interactively"
else
    fail "flatpak runs non-interactively"
fi

# ── GitHub release-API parsing ────────────────────────────────────────────────
group "StreamHub release-API parsing"

release="$(curl -fsSL "https://api.github.com/repos/$STREAMHUB_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/StreamHub\.AppImage' | head -1)"

    [[ "$tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($tag)" \
                                     || fail "tag parses as a version" "$tag"
    check_contains "asset URL ends in StreamHub.AppImage" "StreamHub.AppImage" "$url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$url"

    # The unversioned filename is load-bearing: electron-updater only overwrites
    # in place when the name carries no version. A versioned asset would mean the
    # in-app updater writes a NEW file and every shortcut we create breaks.
    if [[ "$url" =~ StreamHub-[0-9] ]]; then
        fail "asset name carries no version" "$url"
    else
        pass "asset name carries no version (in-place self-update works)"
    fi

    # The URL must actually serve a file — catches a renamed/pulled asset.
    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── the AppImage is verified before it's made executable ──────────────────────
group "StreamHub checksum verification"

# This is the one binary the script downloads and runs directly, so a missing or
# skipped checksum check is a real supply-chain hole, not a nicety.
if grep -qF 'verify_streamhub "$tmp" "$tag" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# A failure to FETCH the checksum must also abort — "couldn't verify" is not
# "verified", and must not degrade into installing the thing anyway.
if awk '/^verify_streamhub\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unfetchable checksum aborts rather than warning"
else
    fail "an unfetchable checksum aborts rather than warning"
fi

# And prove the real thing actually verifies: fetch the published sha512 and
# check it's the right shape (base64 sha512 = 88 chars ending in '==').
if [[ -n "${tag:-}" ]]; then
    yml="$(curl -fsSL "https://github.com/$STREAMHUB_REPO/releases/download/$tag/latest-linux.yml" 2>/dev/null)"
    sha="$(grep -m1 '^sha512:' <<<"$yml" | awk '{print $2}')"
    if [[ ${#sha} -eq 88 ]]; then
        pass "release publishes a base64 sha512 we can check against"
    else
        fail "release publishes a base64 sha512" "got ${#sha} chars: ${sha:0:20}..."
    fi
fi

# ── generated .desktop file ───────────────────────────────────────────────────
group "Generated .desktop file"

APPS_DIR="$tmp"                                   # redirect the writer at a temp dir
STREAMHUB_APPIMAGE="/home/user/.local/bin/StreamHub.AppImage"
STREAMHUB_DIR="/home/user/.local/share/streamhub"
write_streamhub_desktop

desktop="$tmp/com.streamhub.app.desktop"
[[ -f "$desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
content="$(cat "$desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$content"
check_contains "Exec points at the AppImage" "Exec=$STREAMHUB_APPIMAGE" "$content"
check_contains "Icon uses an absolute path"  "Icon=$STREAMHUB_DIR/icon.png" "$content"
check_contains "Type=Application" "Type=Application" "$content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── --dry-run is genuinely inert ──────────────────────────────────────────────
group "--dry-run changes nothing"

fake_home="$tmp/home"
mkdir -p "$fake_home"
before="$(find "$fake_home" | sort)"

out="$(HOME="$fake_home" PROJECTS_DIR="$fake_home/Projects" bash "$SCRIPT" --dry-run 2>&1)"; rc=$?
after="$(find "$fake_home" | sort)"

check_eq "--dry-run exits 0" "0" "$rc"
check_eq "--dry-run creates no files in HOME" "$before" "$after"
check_contains "--dry-run announces itself" "DRY RUN" "$out"
check_contains "--dry-run would install packages" "[dry-run] sudo pacman -S --needed" "$out"
check_contains "--dry-run would clone AgentTileCLI" "[dry-run] git clone" "$out"
check_contains "--dry-run never invokes sudo" "no sudo needed" "$out"

# A dry run must not leave a half-downloaded AppImage anywhere.
if [[ -e "$fake_home/.local/bin/StreamHub.AppImage" ]]; then
    fail "--dry-run downloads no AppImage"
else
    pass "--dry-run downloads no AppImage"
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf '\n%s%d passed, %d failed%s\n' "$BOLD" "$PASS" "$FAIL" "$RESET"
[[ $FAIL -eq 0 ]]
