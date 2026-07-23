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

if awk '/^install_consolevault\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*_amd64.*|| true'; then
    pass "ConsoleVault asset parsing survives a no-match (|| true)"
else
    fail "ConsoleVault asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*DiscRipper.*|| true'; then
    pass "Disc Ripper asset parsing survives a no-match (|| true)"
else
    fail "Disc Ripper asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

# Disc Ripper's release has no signature/checksum asset — it verifies against the
# .zsync's SHA-1/length. Assert the verify step exists and is actually wired into
# the install path, so a refactor can't quietly drop the only integrity check.
if awk '/^verify_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'sha1sum'; then
    pass "Disc Ripper verifies the download against the .zsync sha1"
else
    fail "Disc Ripper verifies the download" "verify_discripper no longer checks a sha1"
fi
if awk '/^install_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_discripper .* || .*die'; then
    pass "Disc Ripper aborts the install on a failed verify"
else
    fail "Disc Ripper aborts on failed verify" "the download is chmod'd without a passing verify"
fi

if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*_amd64.*|| true'; then
    pass "GridDown asset parsing survives a no-match (|| true)"
else
    fail "GridDown asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_dreadkeep\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*castle-of-the-dreadkeep.*|| true'; then
    pass "Castle of the Dreadkeep asset parsing survives a no-match (|| true)"
else
    fail "Castle of the Dreadkeep asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*StalkerGammaGui.*|| true'; then
    pass "Stalker GAMMA GUI asset parsing survives a no-match (|| true)"
else
    fail "Stalker GAMMA GUI asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*LorerimAutoinstall.*|| true'; then
    pass "LoreRim Autoinstall asset parsing survives a no-match (|| true)"
else
    fail "LoreRim Autoinstall asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

# Both new steps must abort rather than chmod an unverified download — same stance
# as the three above, asserted so a refactor can't quietly drop the check.
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_griddown .* || .*die'; then
    pass "GridDown aborts the install on a failed verify"
else
    fail "GridDown aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_dreadkeep\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_dreadkeep .* || .*die'; then
    pass "Castle of the Dreadkeep aborts the install on a failed verify"
else
    fail "Castle of the Dreadkeep aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_gammagui .* || .*die'; then
    pass "Stalker GAMMA GUI aborts the install on a failed verify"
else
    fail "Stalker GAMMA GUI aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_lorerim .* || .*die'; then
    pass "LoreRim Autoinstall aborts the install on a failed verify"
else
    fail "LoreRim Autoinstall aborts on failed verify" "the download is chmod'd without a passing verify"
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
check_eq "taskbar.txt parses to 13 launchers" "13" "${#tb[@]}"

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
    "brave-origin.desktop vesktop.desktop steam.desktop org.keepassxc.KeePassXC.desktop org.kde.dolphin.desktop dev.agenttilecli.AgentTileCli.desktop com.streamhub.app.desktop com.consolevault.app.desktop com.discripper.app.desktop com.griddown.app.desktop com.dreadkeep.castle.desktop com.stalkergamma.gui.desktop com.lorerim.autoinstall.desktop" \
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

release="$(github_api "https://api.github.com/repos/$STREAMHUB_REPO/releases/latest" 2>/dev/null)"
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

# ── ConsoleVault release-API parsing ──────────────────────────────────────────
group "ConsoleVault release-API parsing"

cv_release="$(github_api "https://api.github.com/repos/$CONSOLEVAULT_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$cv_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    cv_tag="$(printf '%s' "$cv_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    # Same pattern the installer uses: the trailing quote is what excludes the
    # sibling .AppImage.sig asset.
    cv_url="$(printf '%s' "$cv_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$cv_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($cv_tag)" \
                                        || fail "tag parses as a version" "$cv_tag"
    check_contains "asset URL ends in _amd64.AppImage" "_amd64.AppImage" "$cv_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$cv_url"

    # The pattern must not pick up the detached signature as the download target.
    if [[ "$cv_url" == *.sig ]]; then
        fail "asset URL is the AppImage, not the .sig" "$cv_url"
    else
        pass "asset URL is the AppImage, not the .sig"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$cv_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── the AppImage is verified before it's made executable ──────────────────────
group "ConsoleVault signature verification"

# Same supply-chain concern as StreamHub: this binary is downloaded and then run
# with the user's privileges, so verification can't be skippable.
if grep -qF 'verify_consolevault "$tmp" "$url" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# An unfetchable/undecodable signature must abort, not warn-and-continue.
if awk '/^verify_consolevault\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable signature aborts rather than warning"
else
    fail "an unverifiable signature aborts rather than warning"
fi

# The public key is hard-coded, never fetched from the release host (which would
# defeat the point). Prove nothing in the verify path pulls the key off the wire.
if awk '/^verify_consolevault\(\)/,/^}/' "$SCRIPT" | grep -qi 'pubkey.*curl\|curl.*pubkey\|tauri.conf'; then
    fail "public key is embedded, not fetched at runtime"
else
    pass "public key is embedded, not fetched at runtime"
fi

# And prove the real thing verifies: fetch the signed AppImage + its .sig and run
# minisign against the embedded key. Skipped where minisign or the net is absent.
if have minisign && [[ -n "${cv_tag:-}" && -n "${cv_url:-}" ]]; then
    cvd="$(mktemp -d)"
    if curl -fsSL "$cv_url" -o "$cvd/app.AppImage" 2>/dev/null \
       && curl -fsSL "$cv_url.sig" 2>/dev/null | base64 -d > "$cvd/app.AppImage.minisig" 2>/dev/null; then
        if minisign -Vm "$cvd/app.AppImage" -x "$cvd/app.AppImage.minisig" -P "$CONSOLEVAULT_PUBKEY" >/dev/null 2>&1; then
            pass "real release verifies against the embedded public key"
        else
            fail "real release verifies against the embedded public key" "minisign rejected it"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live verify\n' "$DIM" "$RESET"
    fi
    rm -rf "$cvd"
else
    printf '  %s·%s minisign not installed — skipping live signature check\n' "$DIM" "$RESET"
fi

# ── generated .desktop file ───────────────────────────────────────────────────
group "ConsoleVault .desktop file"

APPS_DIR="$tmp"
CONSOLEVAULT_APPIMAGE="/home/user/.local/bin/ConsoleVault.AppImage"
CONSOLEVAULT_DIR="/home/user/.local/share/consolevault"
write_consolevault_desktop

cv_desktop="$tmp/com.consolevault.app.desktop"
[[ -f "$cv_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
cv_content="$(cat "$cv_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$cv_content"
check_contains "Exec points at the AppImage" "Exec=$CONSOLEVAULT_APPIMAGE" "$cv_content"
check_contains "Icon uses an absolute path"  "Icon=$CONSOLEVAULT_DIR/icon.png" "$cv_content"
check_contains "Type=Application" "Type=Application" "$cv_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$cv_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── GridDown release-API parsing ──────────────────────────────────────────────
group "GridDown release-API parsing"

gd_release="$(github_api "https://api.github.com/repos/$GRIDDOWN_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$gd_release" || "$gd_release" == *'"Not Found"'* ]]; then
    # GridDown's first release may not be published yet; the installer dies with a
    # clear message in that case, which is the intended behaviour, not a test bug.
    printf '  %s·%s no published release yet — skipping live release checks\n' "$DIM" "$RESET"
else
    pass "fetched the latest release"

    gd_tag="$(printf '%s' "$gd_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    gd_url="$(printf '%s' "$gd_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$gd_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($gd_tag)" \
                                        || fail "tag parses as a version" "$gd_tag"
    check_contains "asset URL ends in _amd64.AppImage" "_amd64.AppImage" "$gd_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$gd_url"

    if [[ "$gd_url" == *.sig ]]; then
        fail "asset URL is the AppImage, not the .sig" "$gd_url"
    else
        pass "asset URL is the AppImage, not the .sig"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$gd_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── GridDown signature verification ───────────────────────────────────────────
group "GridDown signature verification"

if grep -qF 'verify_griddown "$tmp" "$url" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# A repo with no published release yet must warn+skip, not abort the whole run —
# but only for 404. A release that exists with a bad/missing asset must still die,
# so the skip can't quietly become a blanket "ignore all failures".
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q '"404"'; then
    pass "no published release warns and skips rather than aborting the run"
else
    fail "no published release warns and skips" "an unreleased app would kill the whole installer"
fi
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'no GridDown _amd64.AppImage asset.*\|| die\|die "no GridDown'; then
    pass "a published release with no AppImage asset still dies"
else
    fail "a published release with no AppImage asset still dies" "the 404 skip may have swallowed real failures"
fi

if awk '/^verify_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable signature aborts rather than warning"
else
    fail "an unverifiable signature aborts rather than warning"
fi

# The key is embedded, never pulled off the wire from the host it vouches for.
if awk '/^verify_griddown\(\)/,/^}/' "$SCRIPT" | grep -qi 'pubkey.*curl\|curl.*pubkey\|tauri.conf'; then
    fail "public key is embedded, not fetched at runtime"
else
    pass "public key is embedded, not fetched at runtime"
fi

# The pubkey in install.sh must match what the app actually ships in its Tauri
# config (stored there as base64 of the whole minisign key file). A drift here
# means every download would fail verification — catch it at test time.
gd_conf="$(curl -fsSL "https://raw.githubusercontent.com/$GRIDDOWN_REPO/$GRIDDOWN_BRANCH/src-tauri/tauri.conf.json" 2>/dev/null || true)"
if [[ -n "$gd_conf" ]]; then
    gd_conf_key="$(printf '%s' "$gd_conf" | grep -m1 '"pubkey"' | cut -d'"' -f4 | base64 -d 2>/dev/null | tail -1 || true)"
    if [[ -n "$gd_conf_key" ]]; then
        check_eq "embedded pubkey matches the app's tauri.conf.json" "$gd_conf_key" "$GRIDDOWN_PUBKEY"
    else
        printf '  %s·%s couldn'\''t decode the pubkey from tauri.conf.json — skipping\n' "$DIM" "$RESET"
    fi
else
    printf '  %s·%s couldn'\''t fetch tauri.conf.json — skipping pubkey cross-check\n' "$DIM" "$RESET"
fi

# And prove the real release verifies against the embedded key.
if have minisign && [[ -n "${gd_tag:-}" && -n "${gd_url:-}" ]]; then
    gdd="$(mktemp -d)"
    if curl -fsSL "$gd_url" -o "$gdd/app.AppImage" 2>/dev/null \
       && curl -fsSL "$gd_url.sig" 2>/dev/null | base64 -d > "$gdd/app.AppImage.minisig" 2>/dev/null; then
        if minisign -Vm "$gdd/app.AppImage" -x "$gdd/app.AppImage.minisig" -P "$GRIDDOWN_PUBKEY" >/dev/null 2>&1; then
            pass "real release verifies against the embedded public key"
        else
            fail "real release verifies against the embedded public key" "minisign rejected it"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live verify\n' "$DIM" "$RESET"
    fi
    rm -rf "$gdd"
else
    printf '  %s·%s minisign missing or no release — skipping live signature check\n' "$DIM" "$RESET"
fi

# ── GridDown .desktop file ────────────────────────────────────────────────────
group "GridDown .desktop file"

APPS_DIR="$tmp"
GRIDDOWN_APPIMAGE="/home/user/.local/bin/GridDown.AppImage"
GRIDDOWN_DIR="/home/user/.local/share/griddown"
write_griddown_desktop

gd_desktop="$tmp/com.griddown.app.desktop"
[[ -f "$gd_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
gd_content="$(cat "$gd_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$gd_content"
check_contains "Exec points at the AppImage" "Exec=$GRIDDOWN_APPIMAGE" "$gd_content"
check_contains "Icon uses an absolute path"  "Icon=$GRIDDOWN_DIR/icon.png" "$gd_content"
check_contains "Type=Application" "Type=Application" "$gd_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$gd_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── Castle of the Dreadkeep release-API parsing ───────────────────────────────
group "Castle of the Dreadkeep release-API parsing"

dk_release="$(github_api "https://api.github.com/repos/$DREADKEEP_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$dk_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    dk_tag="$(printf '%s' "$dk_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    dk_url="$(printf '%s' "$dk_release" | grep -o 'https://[^"]*/castle-of-the-dreadkeep\.AppImage"' | head -1 | tr -d '"')"

    [[ "$dk_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($dk_tag)" \
                                        || fail "tag parses as a version" "$dk_tag"
    check_contains "asset URL ends in .AppImage" ".AppImage" "$dk_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$dk_url"

    # The pattern must not pick up the .blockmap sibling as the download target.
    if [[ "$dk_url" == *.blockmap ]]; then
        fail "asset URL is the AppImage, not the .blockmap" "$dk_url"
    else
        pass "asset URL is the AppImage, not the .blockmap"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$dk_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── Castle of the Dreadkeep checksum verification ─────────────────────────────
group "Castle of the Dreadkeep checksum verification"

if grep -qF 'verify_dreadkeep "$tmp" "$tag" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_dreadkeep\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# The yml must actually carry a sha512 the installer can read — if electron-builder
# ever changes that format, the installer would refuse every download, and this is
# where we'd find out.
if [[ -n "${dk_tag:-}" ]]; then
    dk_yml="$(curl -fsSL "https://github.com/$DREADKEEP_REPO/releases/download/$dk_tag/latest-linux.yml" 2>/dev/null || true)"
    if [[ -n "$dk_yml" ]]; then
        pass "latest-linux.yml is published in the release"
        dk_sha="$(printf '%s\n' "$dk_yml" | grep -m1 '^ *sha512:' | awk '{print $2}')"
        [[ -n "$dk_sha" ]] && pass "latest-linux.yml carries a sha512" \
                           || fail "latest-linux.yml carries a sha512" "no sha512 line"

        # Prove the digest matches the real asset, using the installer's own
        # base64 conversion — a hex/base64 mixup here would break every install.
        if [[ -n "${dk_url:-}" && -n "$dk_sha" ]]; then
            dkd="$(mktemp -d)"
            if curl -fsSL "$dk_url" -o "$dkd/app.AppImage" 2>/dev/null; then
                dk_actual="$(sha512sum "$dkd/app.AppImage" | awk '{print $1}' | xxd -r -p | base64 -w0)"
                check_eq "real release matches the published sha512" "$dk_sha" "$dk_actual"
            else
                printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
            fi
            rm -rf "$dkd"
        fi
    else
        fail "latest-linux.yml is published in the release" "couldn't fetch it"
    fi
fi

# ── Castle of the Dreadkeep .desktop file ─────────────────────────────────────
group "Castle of the Dreadkeep .desktop file"

APPS_DIR="$tmp"
DREADKEEP_APPIMAGE="/home/user/.local/bin/CastleOfTheDreadkeep.AppImage"
DREADKEEP_DIR="/home/user/.local/share/dreadkeep"
write_dreadkeep_desktop

dk_desktop="$tmp/com.dreadkeep.castle.desktop"
[[ -f "$dk_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
dk_content="$(cat "$dk_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$dk_content"
check_contains "Exec points at the AppImage" "Exec=$DREADKEEP_APPIMAGE" "$dk_content"
check_contains "Icon uses an absolute path"  "Icon=$DREADKEEP_DIR/icon.png" "$dk_content"
check_contains "Type=Application" "Type=Application" "$dk_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$dk_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── Stalker GAMMA GUI release-API parsing ─────────────────────────────────────
group "Stalker GAMMA GUI release-API parsing"

gg_release="$(github_api "https://api.github.com/repos/$GAMMAGUI_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$gg_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    gg_tag="$(printf '%s' "$gg_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    gg_url="$(printf '%s' "$gg_release" | grep -o 'https://[^"]*/StalkerGammaGui-x86_64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$gg_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($gg_tag)" \
                                        || fail "tag parses as a version" "$gg_tag"
    check_contains "asset URL ends in the AppImage name" "$GAMMAGUI_ASSET" "$gg_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$gg_url"

    # The stable asset name is load-bearing: a versioned name would break the
    # installer's grep and every re-run's update path.
    if [[ "$gg_url" =~ StalkerGammaGui-[0-9] ]]; then
        fail "asset name carries no version" "$gg_url"
    else
        pass "asset name carries no version (re-run updates keep working)"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$gg_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── Stalker GAMMA GUI checksum verification ───────────────────────────────────
group "Stalker GAMMA GUI checksum verification"

if grep -qF 'verify_gammagui "$tmp" "$digest" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# The API's per-asset digest is the only checksum this release publishes — prove
# it's actually there and the right shape, using the installer's own extraction.
# If GitHub ever drops or renames the field, the installer would refuse every
# download, and this is where we'd find out.
if [[ -n "$gg_release" ]]; then
    gg_digest="$(printf '%s' "$gg_release" | GAMMAGUI_ASSET="$GAMMAGUI_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["GAMMAGUI_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null)"
    if [[ "$gg_digest" =~ ^[0-9a-f]{64}$ ]]; then
        pass "releases API carries a sha256 digest for the asset"
    else
        fail "releases API carries a sha256 digest" "got: ${gg_digest:-nothing}"
    fi

    # Prove the digest matches the real asset — a mismatch here means either a
    # bad release or a broken verify path, and both would refuse every install.
    if [[ -n "${gg_url:-}" && "$gg_digest" =~ ^[0-9a-f]{64}$ ]]; then
        ggd="$(mktemp -d)"
        if curl -fsSL "$gg_url" -o "$ggd/app.AppImage" 2>/dev/null; then
            gg_actual="$(sha256sum "$ggd/app.AppImage" | awk '{print $1}')"
            check_eq "real release matches the API's sha256 digest" "$gg_digest" "$gg_actual"
        else
            printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
        fi
        rm -rf "$ggd"
    fi
fi

# ── Stalker GAMMA GUI .desktop file ───────────────────────────────────────────
group "Stalker GAMMA GUI .desktop file"

APPS_DIR="$tmp"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop

gg_desktop="$tmp/com.stalkergamma.gui.desktop"
[[ -f "$gg_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
gg_content="$(cat "$gg_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$gg_content"
check_contains "Exec points at the AppImage" "Exec=$GAMMAGUI_APPIMAGE" "$gg_content"
check_contains "Icon uses an absolute path"  "Icon=$GAMMAGUI_DIR/icon.png" "$gg_content"
check_contains "Type=Application" "Type=Application" "$gg_content"
# The WM_CLASS comes from the .NET assembly name, matching the app's own AppDir
# .desktop — a drift here brings back the duplicate-taskbar-icon problem.
check_contains "StartupWMClass matches the Avalonia assembly" "StartupWMClass=StalkerGamma.Gui" "$gg_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$gg_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── competing launcher pruning ────────────────────────────────────────────────
# A launcher left behind by a manual install claims the same StartupWMClass as
# ours, so KDE binds the running window to whichever it finds first. When it
# picks the stray, the pinned icon never lights up and the app opens a second
# taskbar entry beside it.
group "Competing launcher pruning"

# The real one shells out to kbuildsycoca6, which would rebuild the running
# session's KDE cache — the suite installs nothing and changes nothing.
# Nothing later in this file calls it in-process (the --dry-run tests run
# install.sh as a subprocess), so a no-op for the rest of the run is safe.
refresh_desktop_db() { :; }

prune_dir="$tmp/prune"
mkdir -p "$prune_dir"
APPS_DIR="$prune_dir"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop

# what a manual install leaves behind: same window class, different Exec
cat > "$prune_dir/stalker-gamma-gui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Stalker GAMMA GUI
Exec="/home/user/.local/bin/StalkerGammaGui-x86_64.appimage"
Icon=stalker-gamma-gui
StartupWMClass=StalkerGamma.Gui
EOF

# an unrelated launcher that must survive untouched
cat > "$prune_dir/com.example.other.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Something Else
Exec=/usr/bin/true
StartupWMClass=Something.Else
EOF

DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop"

[[ ! -f "$prune_dir/stalker-gamma-gui.desktop" ]] \
    && pass "removes a stray launcher claiming the same StartupWMClass" \
    || fail "removes a stray launcher claiming the same StartupWMClass" "it survived"
[[ -f "$prune_dir/com.stalkergamma.gui.desktop" ]] \
    && pass "keeps our own launcher" \
    || fail "keeps our own launcher" "it was deleted"
[[ -f "$prune_dir/com.example.other.desktop" ]] \
    && pass "leaves unrelated launchers alone" \
    || fail "leaves unrelated launchers alone" "it was deleted"

# --dry-run must not delete: the suite guarantees a dry run changes nothing.
prune_dry="$tmp/prune-dry"
mkdir -p "$prune_dry"
APPS_DIR="$prune_dry"
write_gammagui_desktop
cp "$prune_dir/com.example.other.desktop" "$prune_dry/" 2>/dev/null
cat > "$prune_dry/stalker-gamma-gui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Stalker GAMMA GUI
StartupWMClass=StalkerGamma.Gui
EOF

DRY_RUN=1
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null
DRY_RUN=0

[[ -f "$prune_dry/stalker-gamma-gui.desktop" ]] \
    && pass "--dry-run reports but deletes nothing" \
    || fail "--dry-run reports but deletes nothing" "the stray was removed during a dry run"

# The class is a literal, not a pattern. Every class here contains a dot —
# StalkerGamma.Gui, Lorerim.Gui — and an unescaped dot in a regex matches any
# character, so a launcher for a different app would be deleted.
prune_re="$tmp/prune-regex"
mkdir -p "$prune_re"
APPS_DIR="$prune_re"
printf '[Desktop Entry]\nStartupWMClass=StalkerGammaXGui\n' > "$prune_re/innocent.desktop"
DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_re/innocent.desktop" ]] \
    && pass "matches the window class literally, not as a regex" \
    || fail "matches the window class literally, not as a regex" \
            "a launcher for StalkerGammaXGui was deleted by the dot in StalkerGamma.Gui"

# Claiming a removal that didn't happen is worse than the duplicate icon: it
# reports the problem fixed while it is still there.
if [[ "$(id -u)" -eq 0 ]]; then
    printf '  %s·%s running as root — skipping the unremovable-file check\n' "$DIM" "$RESET"
else
    prune_ro="$tmp/prune-readonly"
    mkdir -p "$prune_ro"
    APPS_DIR="$prune_ro"
    printf '[Desktop Entry]\nStartupWMClass=StalkerGamma.Gui\n' > "$prune_ro/stuck.desktop"
    chmod 500 "$prune_ro"
    prune_msg="$(prune_competing_launchers "com.stalkergamma.gui.desktop" 2>&1)"
    chmod 700 "$prune_ro"

    if [[ -f "$prune_ro/stuck.desktop" && "$prune_msg" == *"removed stuck.desktop"* ]]; then
        fail "doesn't claim to have removed a file it couldn't" "$prune_msg"
    else
        pass "doesn't claim to have removed a file it couldn't"
    fi
fi

# The class is read from the launcher we wrote rather than passed in at each
# call site. Seven apps would otherwise repeat the literal seven times, and
# these do drift — 63b72a5 changed GridDown's from GridDown to griddown.
prune_derive="$tmp/prune-derive"
mkdir -p "$prune_derive"
APPS_DIR="$prune_derive"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop
printf '[Desktop Entry]\nStartupWMClass=StalkerGamma.Gui\n' > "$prune_derive/stray.desktop"
DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ ! -f "$prune_derive/stray.desktop" ]] \
    && pass "reads the window class from the launcher it keeps" \
    || fail "reads the window class from the launcher it keeps" "the stray survived"

# Nothing to compare against must mean nothing is touched. If a missing or
# class-less launcher yielded an empty class, a loose match would sweep the
# whole directory.
prune_none="$tmp/prune-noclass"
mkdir -p "$prune_none"
APPS_DIR="$prune_none"
printf '[Desktop Entry]\nName=Some Other App\nExec=/usr/bin/true\n' > "$prune_none/bystander.desktop"
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_none/bystander.desktop" ]] \
    && pass "a missing launcher prunes nothing" \
    || fail "a missing launcher prunes nothing" "it deleted an unrelated launcher"

printf '[Desktop Entry]\nName=Ours\nExec=/usr/bin/true\n' > "$prune_none/com.stalkergamma.gui.desktop"
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_none/bystander.desktop" ]] \
    && pass "a launcher with no StartupWMClass prunes nothing" \
    || fail "a launcher with no StartupWMClass prunes nothing" "an empty class matched everything"

# A stray can sit beside a perfectly good launcher, so the prune cannot live in
# the launcher-repair branch — that only fires when ours is missing or stale.
# It has to run on the already-installed path too, or a re-run never fixes it.
gg_skip_block="$(awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" \
                 | awk '/already installed \(no self-updater/,/^        return$/')"
if grep -q 'prune_competing_launchers' <<<"$gg_skip_block"; then
    pass "the already-installed path still prunes strays"
else
    fail "the already-installed path still prunes strays" \
         "a matching version stamp returns before any pruning happens"
fi

# Every app that writes a launcher prunes competitors for it, on both the
# already-installed path and the install path — so a new app added later can't
# quietly skip it.
for app in streamhub consolevault discripper griddown dreadkeep gammagui lorerim; do
    app_block="$(awk "/^install_$app\\(\\)/,/^}/" "$SCRIPT")"
    n="$(grep -c 'prune_competing_launchers' <<<"$app_block")"
    if [[ "$n" -ge 2 ]]; then
        pass "install_$app prunes competing launchers"
    else
        fail "install_$app prunes competing launchers" "only $n call(s) — expected the skip and install paths"
    fi
done

# ── GitHub API access ─────────────────────────────────────────────────────────
# Unauthenticated callers get 60 requests/hour per IP, and GitHub answers 403 —
# not 429 — once they're spent. Reading that as "couldn't reach the API" sends
# you hunting for a network fault that isn't there.
group "GitHub API access"

GH_TOKEN="from-gh-token"; GITHUB_TOKEN="from-github-token"
check_eq "GH_TOKEN wins over GITHUB_TOKEN" "from-gh-token" "$(github_token)"

unset GH_TOKEN
check_eq "falls back to GITHUB_TOKEN" "from-github-token" "$(github_token)"

GH_TOKEN=$'padded-token\n'
check_eq "strips newlines so the auth header stays valid" "padded-token" "$(github_token)"
unset GH_TOKEN GITHUB_TOKEN

gh() { printf 'tok-from-gh\n'; }          # the real binary exists, so `have gh` is true
check_eq "falls back to the gh CLI" "tok-from-gh" "$(github_token)"
unset -f gh

rl_body='{"message":"API rate limit exceeded for 1.2.3.4.","documentation_url":"https://docs.github.com/"}'

msg="$(github_api_diagnose 403 "$rl_body" 0 2>&1)"
check_contains "a 403 rate-limit names the rate limit" "rate limit" "$msg"
check_contains "an unauthenticated 403 suggests a token" "GH_TOKEN" "$msg"

msg="$(github_api_diagnose 403 "$rl_body" 1 2>&1)"
if [[ "$msg" != *"gh auth login"* ]]; then
    pass "an authenticated 403 doesn't suggest logging in again"
else
    fail "an authenticated 403 doesn't suggest logging in again" "$msg"
fi

msg="$(github_api_diagnose 403 '{"message":"Resource not accessible"}' 0 2>&1)"
if [[ "$msg" != *"rate limit"* ]]; then
    pass "a non-rate-limit 403 isn't blamed on the rate limit"
else
    fail "a non-rate-limit 403 isn't blamed on the rate limit" "$msg"
fi

msg="$(github_api_diagnose 404 '{"message":"Not Found"}' 0 2>&1)"
check_contains "a 404 is reported as a missing repo or release" "404" "$msg"

# curl's own -w writes the status line even when the transfer fails, so adding
# another on the error path leaves two — and the body then reads "\n000"
# instead of empty. Only the status is parsed today, so this is latent, but any
# caller that reads the body of a failed request would get that garbage.
unreachable="$(github_api_raw "https://nonexistent.invalid.example/x" 2>/dev/null)"
check_eq "an unreachable host reports status 000" "000" "${unreachable##*$'\n'}"
check_eq "an unreachable host leaves an empty body" "" "${unreachable%$'\n'*}"

# Every release lookup must go through the helper, or it stays unauthenticated
# and keeps reporting a rate-limit refusal as a network failure. Matches any
# curl against /repos, not one spelling of it — the first version of this check
# only looked for `curl -fsSL` and sailed past GridDown's `curl -sSL -w`.
bypass="$(grep -n 'curl[^|]*api\.github\.com/repos' "$SCRIPT" || true)"
if [[ -z "$bypass" ]]; then
    pass "no release lookup bypasses the API helper"
else
    fail "no release lookup bypasses the API helper" "$bypass"
fi

# GridDown may not have cut a release yet, so it alone treats 404 as "skip and
# carry on". Routing it through the helper must not cost it that.
gd_block="$(awk '/^install_griddown\(\)/,/^}/' "$SCRIPT")"
if grep -q 'github_api_raw' <<<"$gd_block"; then
    pass "GridDown fetches through the helper too"
else
    fail "GridDown fetches through the helper too" "it still calls curl directly"
fi
if grep -q '"404"' <<<"$gd_block"; then
    pass "GridDown still skips gracefully when there is no release"
else
    fail "GridDown still skips gracefully when there is no release" "the 404 branch is gone"
fi

# ── LoreRim Autoinstall release-API parsing ───────────────────────────────────
group "LoreRim Autoinstall release-API parsing"

lr_release="$(github_api "https://api.github.com/repos/$LORERIM_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$lr_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited? no release published yet?)"
else
    pass "fetched the latest release"

    lr_tag="$(printf '%s' "$lr_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    lr_url="$(printf '%s' "$lr_release" | grep -o 'https://[^"]*/LorerimAutoinstall-x86_64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$lr_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($lr_tag)" \
                                        || fail "tag parses as a version" "$lr_tag"
    check_contains "asset URL ends in the AppImage name" "$LORERIM_ASSET" "$lr_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$lr_url"

    # The stable asset name is load-bearing: a versioned name would break the
    # installer's grep and every re-run's update path.
    if [[ "$lr_url" =~ LorerimAutoinstall-[0-9] ]]; then
        fail "asset name carries no version" "$lr_url"
    else
        pass "asset name carries no version (re-run updates keep working)"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$lr_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── LoreRim Autoinstall checksum verification ─────────────────────────────────
group "LoreRim Autoinstall checksum verification"

if grep -qF 'verify_lorerim "$tmp" "$digest" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# The API's per-asset digest is the only checksum this release publishes — prove
# it's actually there and the right shape, using the installer's own extraction.
# If GitHub ever drops or renames the field, the installer would refuse every
# download, and this is where we'd find out.
if [[ -n "$lr_release" ]]; then
    lr_digest="$(printf '%s' "$lr_release" | LORERIM_ASSET="$LORERIM_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["LORERIM_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null)"
    if [[ "$lr_digest" =~ ^[0-9a-f]{64}$ ]]; then
        pass "releases API carries a sha256 digest for the asset"
    else
        fail "releases API carries a sha256 digest" "got: ${lr_digest:-nothing}"
    fi

    # Prove the digest matches the real asset — a mismatch here means either a
    # bad release or a broken verify path, and both would refuse every install.
    if [[ -n "${lr_url:-}" && "$lr_digest" =~ ^[0-9a-f]{64}$ ]]; then
        lrd="$(mktemp -d)"
        if curl -fsSL "$lr_url" -o "$lrd/app.AppImage" 2>/dev/null; then
            lr_actual="$(sha256sum "$lrd/app.AppImage" | awk '{print $1}')"
            check_eq "real release matches the API's sha256 digest" "$lr_digest" "$lr_actual"
        else
            printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
        fi
        rm -rf "$lrd"
    fi
fi

# ── LoreRim Autoinstall .desktop file ─────────────────────────────────────────
group "LoreRim Autoinstall .desktop file"

APPS_DIR="$tmp"
LORERIM_APPIMAGE="/home/user/.local/bin/LorerimAutoinstall.AppImage"
LORERIM_DIR="/home/user/.local/share/lorerim-autoinstall"
write_lorerim_desktop

lr_desktop="$tmp/com.lorerim.autoinstall.desktop"
[[ -f "$lr_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
lr_content="$(cat "$lr_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$lr_content"
check_contains "Exec points at the AppImage" "Exec=$LORERIM_APPIMAGE" "$lr_content"
check_contains "Icon uses an absolute path"  "Icon=$LORERIM_DIR/icon.png" "$lr_content"
check_contains "Type=Application" "Type=Application" "$lr_content"
# The WM_CLASS comes from the .NET assembly name, matching the app's own AppDir
# .desktop — a drift here brings back the duplicate-taskbar-icon problem.
check_contains "StartupWMClass matches the Avalonia assembly" "StartupWMClass=Lorerim.Gui" "$lr_content"
# The app's own .desktop registers the jackify: URL scheme (Nexus download
# links); dropping it here would silently break click-to-download.
check_contains "registers the jackify: scheme handler" "MimeType=x-scheme-handler/jackify;" "$lr_content"
check_contains "Exec takes the URL argument (%u)" "%u" "$lr_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$lr_desktop" 2>&1)"; then
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

# Hand the child a token explicitly. It runs under a fake HOME, so `gh` can't
# find its config and the run would fall back to the 60/hour unauthenticated
# budget — making this assertion about dry-run inertness fail for an unrelated
# reason whenever that budget happens to be spent.
#
# Resolve it BEFORE the command rather than as an assignment prefix: earlier
# prefixes are visible to later expansions, so `HOME=... GH_TOKEN="$(github_token)"`
# would look the token up under the fake HOME and find nothing.
gh_tok="$(github_token)"
out="$(HOME="$fake_home" PROJECTS_DIR="$fake_home/Projects" GH_TOKEN="$gh_tok" \
       bash "$SCRIPT" --dry-run 2>&1)"; rc=$?
after="$(find "$fake_home" | sort)"

check_eq "--dry-run exits 0" "0" "$rc"
check_eq "--dry-run creates no files in HOME" "$before" "$after"
check_contains "--dry-run announces itself" "DRY RUN" "$out"
check_contains "--dry-run would install packages" "[dry-run] sudo pacman -S --needed" "$out"
check_contains "--dry-run would clone AgentTileCLI" "[dry-run] git clone" "$out"
check_contains "--dry-run never invokes sudo" "no sudo needed" "$out"

# A dry run must not leave a half-downloaded AppImage anywhere.
if [[ -e "$fake_home/.local/bin/StreamHub.AppImage" || -e "$fake_home/.local/bin/ConsoleVault.AppImage" \
   || -e "$fake_home/.local/bin/GridDown.AppImage" || -e "$fake_home/.local/bin/CastleOfTheDreadkeep.AppImage" \
   || -e "$fake_home/.local/bin/StalkerGammaGui.AppImage" || -e "$fake_home/.local/bin/LorerimAutoinstall.AppImage" ]]; then
    fail "--dry-run downloads no AppImage"
else
    pass "--dry-run downloads no AppImage"
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf '\n%s%d passed, %d failed%s\n' "$BOLD" "$PASS" "$FAIL" "$RESET"
[[ $FAIL -eq 0 ]]
