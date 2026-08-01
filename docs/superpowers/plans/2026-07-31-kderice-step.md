# KDE Rice Step Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 13th step to `install.sh` that clones, builds, installs and — when the machine's monitors match — applies the [kderice](https://github.com/pl0xuee/kderice) KDE Plasma rice.

**Architecture:** One new function `install_kderice()` plus three small pure helpers, following the existing `install_agenttilecli()` clone-and-build pattern. The step runs last, after `configure_system`, because `configure_taskbar` rewrites the panel and restarts plasmashell. Applying is gated on kderice's own `generate/check_geometry.py`, because `palette.toml` hardcodes one machine's monitor layout and Plasma containment ids.

**Tech Stack:** Bash 5 (`set -euo pipefail`), Python 3.11+ (`tomllib`), `kscreen-doctor`, pacman. Tests are `tests/run.sh` — a plain bash suite that `source`s `install.sh` and calls its functions directly.

**Spec:** `docs/superpowers/specs/2026-07-31-kderice-step-design.md`

## Global Constraints

- The whole script is idempotent. A second run must be a near no-op — that is what makes the wallpaper skip logic mandatory rather than an optimisation.
- `install.sh` runs under `set -euo pipefail`. Any command whose failure is tolerable must be guarded (`|| true`, an `if`, or `|| { ...; return 0; }`), or it kills the run.
- The step must never be fatal. It warns, calls `report`, and `return 0`. Precedent: `install_discripper`.
- Every sub-script shelled out to gets `< /dev/null`. `tests/run.sh` asserts this by grep; a prompt with no tty hangs a real terminal run forever.
- `pacman` is always invoked with `--noconfirm`; `tests/run.sh` asserts this by grep.
- Dry run changes nothing: no clone, no build, no files under `$HOME`. `tests/run.sh` asserts this by diffing a fake `$HOME` before and after.
- Comments explain *why*, not *what* — match the density and voice of the surrounding file.
- Run `./tests/run.sh` after every task. It must stay at 0 failures.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `packages/pacman.txt` | modify | Declare the six new repo packages kderice needs |
| `install.sh` | modify | Constants (after line 130), `usage()` text, `--only` validation, `STEP_TOTAL`, new `# ── 13. KDE Rice` section before `main()`, the `wanted kderice` line in `main()`, the closing "Run them" list |
| `tests/run.sh` | modify | New assertions in the existing "Argument handling", "Package-list parser" and "--dry-run changes nothing" groups, plus one new "KDE Rice" group |
| `README.md` | modify | Note the rice is applied at the end, and how to revert |

No new files. The repo is deliberately three files plus a package directory; adding a fourth would break a structure the README documents.

---

### Task 1: Declare kderice's packages

**Files:**
- Modify: `packages/pacman.txt` (append a new section at the end, before the "Optional extras" block)
- Test: `tests/run.sh` ("Package-list parser" group, after the `flatpak` assertion around line 235)

**Interfaces:**
- Consumes: nothing
- Produces: the six package names `python-numpy`, `python-pillow`, `ttf-fira-mono`, `qt6-imageformats`, `kscreen`, `rsync` present in `packages/pacman.txt`. Task 3's `kderice_deps()` installs exactly these names when they are missing.

- [ ] **Step 1: Write the failing test**

In `tests/run.sh`, inside the "Package-list parser" group, immediately after the block that asserts `pacman.txt installs flatpak` (it ends with the `fi` closing `if [[ ${#fp[@]} -gt 0 ]]`), add:

```bash
# kderice generates its wallpapers with numpy+Pillow, renders them as WebP that
# Qt can only read through qt6-imageformats, refuses to apply without Fira Mono,
# installs them with rsync, and is gated on kscreen-doctor's view of the
# monitors. A missing one of these fails inside kderice, where the error is
# much harder to read than it is here.
for p in python-numpy python-pillow ttf-fira-mono qt6-imageformats kscreen rsync; do
    if printf '%s\n' "${real[@]}" | grep -qx "$p"; then
        pass "pacman.txt installs $p (kderice)"
    else
        fail "pacman.txt installs $p (kderice)" "kderice needs it"
    fi
done
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/run.sh 2>&1 | grep -E 'kderice|failed'`
Expected: six lines reading `✗ pacman.txt installs <name> (kderice)`, and a non-zero failure count in the summary.

- [ ] **Step 3: Add the packages**

In `packages/pacman.txt`, insert this section between the "Build toolchain" block (which ends with the `minisign` line) and the `# ── Optional extras ──` heading:

```
# ── KDE rice (kderice) ────────────────────────────────────────────────
# Wallpapers are generated, not shipped: 51 terrain variants rendered at
# every output resolution.
python-numpy                 # kderice: wallpaper generation
python-pillow                # kderice: wallpaper generation
# The slides are lossless WebP. Qt reads WebP only through this plugin —
# without it Plasma shows a black desktop and no error.
qt6-imageformats
# 'kderice apply' hard-fails without this font. Installing it here also
# means 'kderice setup' never has to sudo for it, so it can't stop to
# prompt in the middle of an unattended run.
ttf-fira-mono
kscreen                      # kscreen-doctor — the monitor-geometry gate
rsync                        # kderice apply installs the wallpapers with it
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: the six `✓ pacman.txt installs <name> (kderice)` lines, the existing "all N packages found in enabled repos" still passes (all six resolve in the CachyOS/Arch repos — verified), and the summary reports `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add packages/pacman.txt tests/run.sh
git commit -m "Declare kderice's package dependencies"
```

---

### Task 2: Wire the step into the run

**Files:**
- Modify: `install.sh` — constants after line 130, `STEP_TOTAL` at line 187, `usage()` at lines 341-344 and 360, the `--only` `die` string at line 370, the validation `case` at lines 380-381, a new section before `main()`, and the `wanted` list in `main()`
- Test: `tests/run.sh` ("Argument handling" group, after the existing `--only nonsense` assertion around line 56)

**Interfaces:**
- Consumes: `step()`, `report()`, `PROJECTS_DIR` — all already defined in `install.sh`
- Produces: `KDERICE_REPO`, `KDERICE_DIR`, and `install_kderice()` (no arguments, always returns 0). Tasks 3-6 fill this function in.

- [ ] **Step 1: Write the failing tests**

In `tests/run.sh`, inside the "Argument handling" group, right after the two lines asserting `--only rejects an invalid step`, add:

```bash
out="$(bash "$SCRIPT" --only kderice --dry-run 2>&1)"; rc=$?
check_eq "--only kderice is accepted" "0" "$rc"
check_contains "--only error text names kderice" "kderice" \
    "$(bash "$SCRIPT" --only nonsense 2>&1)"
check_contains "--help documents the kderice step" "kderice" \
    "$(bash "$SCRIPT" --help 2>&1)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/run.sh 2>&1 | grep -E 'kderice|failed'`
Expected: `✗ --only kderice is accepted` (exit 1 — the validation `case` rejects it), plus the two `✗ ... names kderice` / `documents the kderice step` failures.

- [ ] **Step 3: Add the constants**

In `install.sh`, after the `WOTLK_SUMS="SHA256SUMS"` line (line 130) and before the `# CPU power profile.` comment, add:

```bash
# kderice — "Gunmetal Filament", a reversible KDE Plasma 6 rice. Not an app but a
# set of edits to the desktop's own config, generated from a single palette file.
#
# Cloned to a permanent path beside the agenttilecli clone, which is what its own
# README assumes (it refers to ../agenttilecli, and derives its palette from that
# app's design system). The clone is also where the rice is re-applied from, so a
# temp dir would not do.
KDERICE_REPO="https://github.com/pl0xuee/kderice.git"
KDERICE_DIR="$PROJECTS_DIR/kderice"
```

- [ ] **Step 4: Bump the step count**

At line 187, change:

```bash
STEP_TOTAL=13    # preflight + 12 steps; recalculated below if --only is used
```

to:

```bash
STEP_TOTAL=14    # preflight + 13 steps; recalculated below if --only is used
```

- [ ] **Step 5: Teach the argument parser about the step**

Three edits, all naming the same list. In `usage()`, change the `--only STEP` block to:

```
  --only STEP     Run one step only:
                    packages | flatpak | agenttilecli | streamhub | consolevault
                    discripper | griddown | dreadkeep | gammagui | lorerim
                    wotlk | config | kderice
```

and change the `Env:` block's `PROJECTS_DIR` line to:

```
  PROJECTS_DIR    Where to clone AgentTileCLI and kderice
                  (default: ~/Documents/Projects)
```

In the `--only` arm of the `while` loop, append ` | kderice` to the `die` string so it reads `... | lorerim | wotlk | config | kderice)"`.

In the validation `case`, append `|kderice` to the accept pattern and ` | kderice` to that `die` string:

```bash
if [[ -n "$ONLY" ]]; then
    case "$ONLY" in
        packages|flatpak|agenttilecli|streamhub|consolevault|discripper|griddown|dreadkeep|gammagui|lorerim|wotlk|config|kderice) ;;
        *) die "--only takes: packages | flatpak | agenttilecli | streamhub | consolevault | discripper | griddown | dreadkeep | gammagui | lorerim | wotlk | config | kderice" ;;
    esac
fi
```

- [ ] **Step 6: Add the stub function and call it**

Immediately before `main()` (after `ensure_path()`'s closing brace), add:

```bash
# ── 13. KDE Rice (Gunmetal Filament) ──────────────────────────────────────────
# A reversible Plasma 6 rice, generated from a palette file rather than shipped
# as a theme. Two things make it unlike every step above.
#
# It is machine-specific by construction: palette.toml declares three monitors by
# name, resolution, scale AND Plasma containment id (43/44/45 — ids Plasma
# assigned on one particular box). On any other layout the slideshow would be
# pointed at containments that don't exist. So applying is gated on kderice's own
# check_geometry.py, and a machine that doesn't match still gets the launcher.
#
# And it runs LAST, after configure_system. configure_taskbar rewrites the
# panel's applet list and restarts plasmashell; kderice's README names re-applying
# afterwards as the supported order. The two own disjoint keys — kderice never
# writes launchers, AppletOrder or hiddenItems — so nothing is lost either way,
# but the snapshot apply takes should be of the panel this script just wrote.
install_kderice() {
    step "KDE Rice"
    return 0
}
```

Then in `main()`, after the `wanted config && configure_system` line, add:

```bash
    wanted kderice      && install_kderice
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: `✓ --only kderice is accepted`, `✓ --only error text names kderice`, `✓ --help documents the kderice step`, summary `0 failed`.

Then eyeball the wiring: `./install.sh --only kderice --dry-run` should print a `[2/2] KDE Rice` step header and exit 0.

- [ ] **Step 8: Commit**

```bash
git add install.sh tests/run.sh
git commit -m "Wire a kderice step into install.sh"
```

---

### Task 3: Dependency guard, clone and pull

**Files:**
- Modify: `install.sh` — the body of `install_kderice()`, plus a new `kderice_deps()` helper above it
- Test: `tests/run.sh` (new "KDE Rice" group, inserted before the `# ── summary ──` block at the end)

**Interfaces:**
- Consumes: `KDERICE_REPO`, `KDERICE_DIR`, `install_kderice()` (Task 2); `have()`, `run()`, `step()`, `info()`, `warn()`, `ok()`, `skip()`, `report()`, `DRY_RUN` (existing)
- Produces: `kderice_deps()` — no arguments, returns 0 when every dependency is present or was installed, 1 otherwise. Tasks 4-6 assume `install_kderice()` has already cloned into `$KDERICE_DIR` and returned early on dry run.

- [ ] **Step 1: Write the failing tests**

In `tests/run.sh`, add a new group immediately before the `# ── summary ─────` comment at the bottom of the file:

```bash
# ── KDE Rice ──────────────────────────────────────────────────────────────────
group "KDE Rice"

# Cloning must follow the AgentTileCLI pattern exactly: fast-forward only, so a
# dev branch or uncommitted work in the clone is never clobbered.
if awk '/^install_kderice\(\)/,/^}/' "$SCRIPT" | grep -q 'git -C .* pull --ff-only'; then
    pass "kderice pulls fast-forward-only"
else
    fail "kderice pulls fast-forward-only" "a plain pull could clobber local work"
fi

# The step runs after configure_system: configure_taskbar rewrites the panel and
# restarts plasmashell, and kderice must snapshot the panel this script wrote.
kd_line="$(grep -n 'wanted kderice' "$SCRIPT" | cut -d: -f1)"
cfg_line="$(grep -n 'wanted config' "$SCRIPT" | cut -d: -f1)"
if [[ -n "$kd_line" && -n "$cfg_line" && "$kd_line" -gt "$cfg_line" ]]; then
    pass "kderice runs after the config step"
else
    fail "kderice runs after the config step" "kderice=$kd_line config=$cfg_line"
fi

# Nothing in this step may be fatal — config has already run by then, and a rice
# that wouldn't apply shouldn't cost the user the rest of a working setup.
if awk '/^install_kderice\(\)/,/^}/' "$SCRIPT" | grep -qE '\bdie\b'; then
    fail "kderice never calls die" "a failed rice would abort the whole run"
else
    pass "kderice never calls die"
fi

# kderice setup can sudo for the font when it's absent, and require_tty would
# then stop and wait. Stdin closed means it can never block an unattended run.
if grep -qF 'bin/kderice setup < /dev/null' "$SCRIPT"; then
    pass "kderice setup is run with stdin closed"
else
    fail "kderice setup is run with stdin closed"
fi
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/run.sh 2>&1 | grep -A20 'KDE Rice'`
Expected: `✗ kderice pulls fast-forward-only`, `✗ kderice setup is run with stdin closed`. The "runs after the config step" and "never calls die" assertions already pass against the Task 2 stub — that is fine, they are guarding against regression.

- [ ] **Step 3: Add the dependency guard**

In `install.sh`, immediately above the `# ── 13. KDE Rice` section header, add:

```bash
# Everything kderice needs from the repos, checked before it can fail deep inside
# a Python traceback or a `die` in its own preflight.
#
# These are all in packages/pacman.txt, so a normal run has them already — but
# `--only kderice` can reach here without the packages step, which is the same
# reason verify_griddown pulls in minisign rather than failing.
kderice_deps() {
    local -a missing=()

    python3 -c 'import numpy, PIL' 2>/dev/null || missing+=(python-numpy python-pillow)
    have rsync          || missing+=(rsync)
    have kscreen-doctor || missing+=(kscreen)
    # fc-match always answers with SOMETHING — it falls back to a default font
    # rather than failing — so the answer has to be inspected, not just its
    # exit status. kderice's own preflight does exactly this.
    [[ "$(fc-match --format='%{file}' 'Fira Mono' 2>/dev/null)" == *FiraMono* ]] \
        || missing+=(ttf-fira-mono)
    # No binary to probe for: this is a Qt image plugin, so its absence shows up
    # as a black desktop, not a missing command.
    pacman -Qq qt6-imageformats >/dev/null 2>&1 || missing+=(qt6-imageformats)

    [[ ${#missing[@]} -eq 0 ]] && return 0

    info "Installing kderice's dependencies (${missing[*]})..."
    run sudo pacman -S --needed --noconfirm "${missing[@]}" && return 0

    warn "couldn't install ${missing[*]} — skipping the rice"
    return 1
}
```

- [ ] **Step 4: Replace the stub body with the clone**

Change `install_kderice()`'s body from `step "KDE Rice"; return 0` to:

```bash
install_kderice() {
    step "KDE Rice"

    kderice_deps || { report "KDE Rice" "SKIPPED (missing dependencies)"; return 0; }

    local dir="$KDERICE_DIR"
    run mkdir -p "$PROJECTS_DIR"

    if [[ -d "$dir/.git" ]]; then
        info "Clone exists — pulling latest..."
        # Fast-forward only, same as AgentTileCLI: local commits, a dev branch or
        # uncommitted palette edits make this refuse rather than clobber them.
        if ! run git -C "$dir" pull --ff-only; then
            warn "couldn't fast-forward $dir (local changes or a dev branch?) — using what's already there"
        fi
    else
        info "Cloning into $dir..."
        if ! run git clone "$KDERICE_REPO" "$dir"; then
            warn "couldn't clone kderice — skipping the rice"
            report "KDE Rice" "SKIPPED (clone failed)"
            return 0
        fi
    fi

    # Everything past here reads files out of the clone, and on a dry run there
    # isn't one — `run git clone` only printed what it would have done.
    if [[ $DRY_RUN -eq 1 ]]; then
        run "(cd $dir && python3 generate/build.py)"
        run "(cd $dir && python3 generate/wallpaper.py)  # only when slides are missing"
        run "(cd $dir && ./bin/kderice setup < /dev/null)"
        run "(cd $dir && ./bin/kderice apply)            # only when the monitors match palette.toml"
        report "KDE Rice" "would clone, build and apply"
        return 0
    fi

    ok "clone ready at $dir"
}
```

Note the literal `./bin/kderice setup < /dev/null` in the dry-run block satisfies the stdin-closed grep; Task 6 adds the real invocation.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: all four "KDE Rice" assertions pass, the "--dry-run changes nothing" group still passes (nothing was cloned into the fake `$HOME`), summary `0 failed`.

Then check the dry run reads right: `./install.sh --only kderice --dry-run` should print `[dry-run] git clone ...` and the four `[dry-run]` lines, and create nothing.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/run.sh
git commit -m "Clone kderice and guard its dependencies"
```

---

### Task 4: Build the palette, generate wallpapers only when missing

**Files:**
- Modify: `install.sh` — two new helpers above `install_kderice()`, and the tail of `install_kderice()`
- Test: `tests/run.sh` ("KDE Rice" group)

**Interfaces:**
- Consumes: `kderice_deps()` and the clone from Task 3
- Produces:
  - `kderice_expected_slides <palette.toml path>` — prints `<count> <format>` on stdout (e.g. `153 webp`), returns non-zero if the file can't be read
  - `kderice_have_slides <dir> <count> <format>` — returns 0 when `<dir>` already holds at least `<count>` files named `*.<format>` at depth ≥ 2, 1 otherwise

- [ ] **Step 1: Write the failing tests**

Append to the "KDE Rice" group in `tests/run.sh`:

```bash
# palette.toml is TOML, which bash cannot read. A hand-rolled parser would break
# the first time a comment happened to look like a key — and the file is more
# comment than key.
kd="$tmp/kderice"; mkdir -p "$kd"
cat > "$kd/palette.toml" <<'EOF'
[wallpaper]
# variants = 999   <- a comment shaped exactly like the key
variants = 4
format   = "webp"
sizes = [
  { w = 100, h = 200, scale = 1.0, containment = 43, output = "DP-1" },
  { w = 300, h = 400, scale = 1.0, containment = 44, output = "DP-2" },
]
EOF
check_eq "expected slide count is variants x outputs" "8 webp" \
    "$(kderice_expected_slides "$kd/palette.toml")"

# Slides live one directory down, named for their resolution. Counting at depth 1
# would count nothing; counting every file would count the contact sheet too.
mkdir -p "$kd/build/wallpapers/100x200" "$kd/build/wallpapers/300x400"
kderice_have_slides "$kd/build/wallpapers" 8 webp \
    && fail "incomplete wallpapers are regenerated" "empty dirs counted as complete" \
    || pass "incomplete wallpapers are regenerated"

for i in 1 2 3 4; do
    : > "$kd/build/wallpapers/100x200/gunmetal-$i-100x200.webp"
    : > "$kd/build/wallpapers/300x400/gunmetal-$i-300x400.webp"
done
kderice_have_slides "$kd/build/wallpapers" 8 webp \
    && pass "complete wallpapers are reused" \
    || fail "complete wallpapers are reused" "would regenerate 590 MB on every re-run"

# A stray PNG contact sheet must not be mistaken for a slide.
: > "$kd/build/wallpapers/preview.png"
kderice_have_slides "$kd/build/wallpapers" 8 png \
    && fail "the contact sheet is not counted as a slide" \
    || pass "the contact sheet is not counted as a slide"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/run.sh 2>&1 | grep -A30 'KDE Rice'`
Expected: `✗ expected slide count is variants x outputs` (got empty — the function doesn't exist), and errors from the two `kderice_have_slides` calls.

- [ ] **Step 3: Add the two helpers**

In `install.sh`, immediately above `kderice_deps()`, add:

```bash
# How many wallpaper slides palette.toml says there should be, and in what
# format. Printed as "<count> <format>".
#
# Via Python's tomllib rather than grep: palette.toml is mostly prose comments,
# and several of them are written as commented-out keys — the exact shape a
# line-based parser would read as real. Nothing in bash reads TOML correctly.
kderice_expected_slides() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    w = tomllib.load(fh)["wallpaper"]
print(w["variants"] * len(w["sizes"]), w.get("format", "png"))
PY
}

# Are the slides already generated? Generating them costs ~90s and ~590 MB, and
# re-running install.sh is supposed to be a no-op.
#
# mindepth 2 because each slide lives in a subdirectory named for its resolution;
# the -name filter because build/wallpapers also holds preview.png, the contact
# sheet, which is not a slide.
kderice_have_slides() {
    local dir="$1" want="$2" fmt="$3" have
    [[ -d "$dir" ]] || return 1
    have="$(find "$dir" -mindepth 2 -type f -name "*.$fmt" 2>/dev/null | wc -l)"
    [[ "$have" -ge "$want" ]]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tests/run.sh 2>&1 | grep -A30 'KDE Rice'`
Expected: `✓ expected slide count is variants x outputs`, `✓ incomplete wallpapers are regenerated`, `✓ complete wallpapers are reused`, `✓ the contact sheet is not counted as a slide`.

- [ ] **Step 5: Use them in the step**

In `install_kderice()`, replace the closing `ok "clone ready at $dir"` line with:

```bash
    info "Building the palette..."
    # build.py asserts WCAG contrast, so a bad colour edit fails here rather than
    # on screen. It's fast — no reason to ever skip it.
    if ! ( cd "$dir" && python3 generate/build.py ); then
        warn "kderice build failed — skipping the rice"
        report "KDE Rice" "SKIPPED (build failed)"
        return 0
    fi

    local want fmt
    read -r want fmt <<<"$(kderice_expected_slides "$dir/palette.toml")"
    if [[ -z "$want" ]]; then
        warn "couldn't read [wallpaper] out of $dir/palette.toml — skipping the rice"
        report "KDE Rice" "SKIPPED (unreadable palette.toml)"
        return 0
    fi

    if kderice_have_slides "$dir/build/wallpapers" "$want" "$fmt"; then
        skip "wallpapers already generated ($want slides)"
    else
        info "Generating $want wallpapers — takes about 90s and ~590 MB..."
        if ! ( cd "$dir" && python3 generate/wallpaper.py ); then
            warn "wallpaper generation failed — skipping the rice"
            report "KDE Rice" "SKIPPED (wallpaper generation failed)"
            return 0
        fi
        ok "$want wallpapers generated"
    fi
```

- [ ] **Step 6: Run the tests and a real partial run**

Run: `./tests/run.sh`
Expected: summary `0 failed`.

Run: `./install.sh --only kderice`
Expected: it clones (or pulls), builds, reports `· wallpapers already generated (153 slides)` on this machine — the clone at `~/Documents/Projects/kderice` may already have them — then stops after the wallpaper block, since apply isn't written yet.

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/run.sh
git commit -m "Build kderice's palette and generate wallpapers only when missing"
```

---

### Task 5: Gate applying on the live monitor geometry

**Files:**
- Modify: `install.sh` — one new helper above `install_kderice()`
- Test: `tests/run.sh` ("KDE Rice" group)

**Interfaces:**
- Consumes: the clone and `build/wallpapers` from Tasks 3-4
- Produces: `kderice_geometry_ok <project_dir> <wallpaper_dir> <kscreen_json>` — returns 0 when the live monitors match `palette.toml`, 1 otherwise. Prints `check_geometry.py`'s per-output diagnosis on stdout. Task 6 calls it to decide whether to apply.

- [ ] **Step 1: Write the failing tests**

Append to the "KDE Rice" group in `tests/run.sh`:

```bash
# check_geometry.py returns 0 on empty stdin — correct for a status command,
# wrong for a gate. No geometry means we don't know, and not knowing must not
# apply a rice pinned to three specific monitors.
kderice_geometry_ok "$kd" "$kd/build/wallpapers" "" >/dev/null 2>&1 \
    && fail "no kscreen output fails the geometry gate" "an unknown layout would be riced" \
    || pass "no kscreen output fails the geometry gate"

kderice_geometry_ok "$kd" "$kd/build/wallpapers" "   " >/dev/null 2>&1 \
    && fail "whitespace-only kscreen output fails the gate" \
    || pass "whitespace-only kscreen output fails the gate"

# The gate must consult kderice's own checker, not a reimplementation of it that
# would drift the moment palette.toml grows a field.
if awk '/^kderice_geometry_ok\(\)/,/^}/' "$SCRIPT" | grep -q 'check_geometry.py'; then
    pass "the gate calls kderice's own check_geometry.py"
else
    fail "the gate calls kderice's own check_geometry.py" "don't reimplement it in bash"
fi

# It must be pointed at build/wallpapers, not the installed directory: the gate
# runs BEFORE apply, and apply is what populates ~/.local/share/wallpapers.
if awk '/install_kderice\(\)/,/^}/' "$SCRIPT" | grep -q 'kderice_geometry_ok .*build/wallpapers'; then
    pass "the gate checks build/wallpapers, not the installed dir"
else
    fail "the gate checks build/wallpapers, not the installed dir" \
         "the installed dir is empty until apply runs, so the gate would always fail"
fi
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/run.sh 2>&1 | grep -A40 'KDE Rice'`
Expected: errors from the two `kderice_geometry_ok` calls (function not found), and `✗ the gate calls kderice's own check_geometry.py`, `✗ the gate checks build/wallpapers, not the installed dir`.

- [ ] **Step 3: Add the helper**

In `install.sh`, immediately below `kderice_have_slides()`, add:

```bash
# Does this machine look like the one palette.toml was written for?
#
# palette.toml pins three monitors by name, resolution, scale AND the Plasma
# containment id each one owns. Applying against a different layout points the
# slideshow at containments that don't exist — the desktop looks fine and the
# wallpaper is simply wrong, which is the failure mode kderice wrote this checker
# to catch in the first place. So the checker is called, never reimplemented:
# a bash copy would drift the moment palette.toml grows a field.
#
# Pointed at build/wallpapers rather than the checker's default
# ~/.local/share/wallpapers/gunmetal, because this runs BEFORE apply and apply is
# what populates that directory.
#
# Empty input is a FAILURE here. check_geometry.py returns 0 for it — right for a
# status command, wrong for a gate: no geometry means we don't know, and not
# knowing must not rice a machine.
kderice_geometry_ok() {
    local proj="$1" walls="$2" json="$3"
    [[ -n "${json// /}" ]] || return 1
    printf '%s' "$json" | python3 "$proj/generate/check_geometry.py" "$walls"
}
```

- [ ] **Step 4: Call it from the step**

In `install_kderice()`, after the wallpaper block added in Task 4, add:

```bash
    local geom=""
    have kscreen-doctor && geom="$(kscreen-doctor -j 2>/dev/null || true)"
    if ! kderice_geometry_ok "$dir" "$dir/build/wallpapers" "$geom"; then
        warn "this machine's monitors don't match kderice's palette.toml — the rice was built but NOT applied"
        warn "fix [wallpaper].sizes in $dir/palette.toml, then: (cd $dir && python3 generate/wallpaper.py && ./bin/kderice apply)"
        report "KDE Rice" "built, NOT applied — monitor layout doesn't match palette.toml"
        return 0
    fi
```

Task 6 inserts the `setup` call *above* this block and the `apply` call below it.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./tests/run.sh 2>&1 | grep -A40 'KDE Rice'`
Expected: all four new assertions pass. Summary `0 failed`.

Sanity-check the gate against the real machine:

```bash
kscreen-doctor -j | python3 ~/Documents/Projects/kderice/generate/check_geometry.py \
    ~/Documents/Projects/kderice/build/wallpapers; echo "exit=$?"
```

Expected on this box: three green `✓ DP-1 / DP-2 / DP-3` lines and `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/run.sh
git commit -m "Gate the rice on kderice's own monitor-geometry check"
```

---

### Task 6: Install the launcher, apply, and report

**Files:**
- Modify: `install.sh` — the tail of `install_kderice()`, and the "Run them" list in `main()` (around line 2683)
- Modify: `README.md`
- Test: `tests/run.sh` ("KDE Rice" group and the "--dry-run changes nothing" group)

**Interfaces:**
- Consumes: `riceable`, `dir`, `want` from Tasks 3-5
- Produces: nothing further — this closes the step.

- [ ] **Step 1: Write the failing tests**

Append to the "KDE Rice" group in `tests/run.sh`:

```bash
# setup runs whether or not the gate passed. A machine the rice can't be applied
# to still gets the KDE Rice launcher, so it can be applied by hand once
# palette.toml is fixed — that's the whole point of gating apply rather than the
# step.
kd_body="$(awk '/^install_kderice\(\)/,/^}/' "$SCRIPT")"
kd_setup="$(grep -n 'bin/kderice setup' <<<"$kd_body" | tail -1 | cut -d: -f1)"
kd_gate="$(grep -n 'kderice_geometry_ok' <<<"$kd_body" | tail -1 | cut -d: -f1)"
if [[ -n "$kd_setup" && -n "$kd_gate" && "$kd_setup" -lt "$kd_gate" ]]; then
    pass "kderice setup runs before the apply gate is consulted"
else
    fail "kderice setup runs before the apply gate is consulted" \
         "setup=$kd_setup gate=$kd_gate — a mismatched machine would get no launcher"
fi

# Whatever happens, the run must say so in the closing report.
if grep -qE 'report "KDE Rice"' <<<"$kd_body"; then
    pass "the step reports its outcome"
else
    fail "the step reports its outcome"
fi

# A rice that didn't apply is the one outcome a user would otherwise not notice —
# their desktop just looks the same. It has to warn, not only report.
if grep -q "don't match" <<<"$kd_body" || grep -q 'NOT applied' <<<"$kd_body"; then
    pass "a gated rice is warned about, not applied silently"
else
    fail "a gated rice is warned about, not applied silently"
fi
```

And in the "--dry-run changes nothing" group, add after the `--dry-run would clone AgentTileCLI` line:

```bash
check_contains "--dry-run would build the rice" "generate/build.py" "$out"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tests/run.sh 2>&1 | grep -E 'kderice|KDE Rice|rice|failed'`
Expected: `✗ kderice setup runs before the apply gate is consulted` and `✗ a gated rice is warned about, not applied silently`. The `--dry-run would build the rice` assertion already passes from Task 3's dry-run block.

- [ ] **Step 3: Add setup above the gate, and apply below it**

Rewrite the tail of `install_kderice()` — everything from the wallpaper block's closing `fi` onward, which is the gate block Task 5 added — as the following. The gate block is unchanged apart from now naming `$commit` in its report; the `setup` block above it and the `apply` block below it are new.

```bash
    # Links kderice and kderice-launch into ~/.local/bin and installs the
    # KDE Rice launcher entry and icon.
    #
    # Before the gate, and unconditional: a machine the rice can't be applied to
    # still gets the toggle, so it can be riced by hand once palette.toml is
    # fixed. Gating apply is the point; gating the install would leave nothing.
    #
    # Stdin closed: setup sudos for the font when it's missing, and its
    # require_tty would otherwise stop and wait forever in an unattended run.
    # ttf-fira-mono is in packages/pacman.txt and kderice_deps re-checks it, so
    # in practice nothing here prompts at all.
    if ! ( cd "$dir" && ./bin/kderice setup < /dev/null ); then
        warn "kderice setup failed — skipping the rice"
        report "KDE Rice" "SKIPPED (setup failed)"
        return 0
    fi
    ok "kderice linked into $BIN_DIR, KDE Rice launcher installed"

    local commit; commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"

    local geom=""
    have kscreen-doctor && geom="$(kscreen-doctor -j 2>/dev/null || true)"
    if ! kderice_geometry_ok "$dir" "$dir/build/wallpapers" "$geom"; then
        warn "this machine's monitors don't match kderice's palette.toml — the rice was built and the launcher installed, but NOT applied"
        warn "fix [wallpaper].sizes in $dir/palette.toml, then: (cd $dir && python3 generate/wallpaper.py && ./bin/kderice apply)"
        report "KDE Rice" "built ($commit), NOT applied — monitor layout doesn't match palette.toml"
        return 0
    fi

    # apply stops and restarts plasmashell itself, through the systemd user unit.
    # Safe here because configure_taskbar has already finished with the panel.
    info "Applying — plasmashell restarts, so the desktop will flicker..."
    if ( cd "$dir" && ./bin/kderice apply ); then
        ok "Gunmetal Filament applied"
        report "KDE Rice" "applied ($commit) — 'kderice restore' puts stock Breeze back"
    else
        warn "kderice apply failed — the desktop is unchanged; run 'kderice status' to see why"
        report "KDE Rice" "built ($commit), apply FAILED — try 'kderice status'"
    fi
}
```

There should be exactly one `local geom` and one `kderice_geometry_ok` call in the function when you are done — Task 5's block is edited in place, not duplicated.

- [ ] **Step 4: Add it to the closing "Run them" list**

In `main()`, after the `WowWotlkAutoinstall.AppImage` line and before the `(or find everything in the app menu)` line, add:

```bash
    printf '    %skderice%s               toggle the desktop rice (%skderice restore%s = stock Breeze)\n' \
        "$BOLD" "$RESET" "$BOLD" "$RESET"
```

- [ ] **Step 5: Update the README**

In `README.md`, add a row to the "What goes where" table after the `install.sh` row:

```markdown
| the KDE rice | cloned to `~/Documents/Projects/kderice`, built and applied at the end |
```

And add this paragraph after the "Close Brave and KeePassXC first." note:

```markdown
**The desktop rice is applied last.** `install.sh` clones
[kderice](https://github.com/pl0xuee/kderice) and applies it after the panel is
configured — plasmashell restarts, so the desktop flickers once. `kderice
restore` puts stock Breeze back, and the **KDE Rice** entry in the app launcher
toggles between them. On a machine whose monitors don't match kderice's
`palette.toml`, the rice is built and the launcher installed but nothing is
applied, and the run says so.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: every "KDE Rice" assertion passes, `✓ --dry-run would build the rice`, `✓ --dry-run creates no files in HOME`, summary `0 failed`.

- [ ] **Step 7: Verify against the real machine**

Run: `./install.sh --only kderice`

Expected on this box (its monitors match `palette.toml`): the clone pulls, the palette builds, wallpapers are reused, setup reports the launcher, the gate prints three green `✓ DP-N` lines, apply runs, plasmashell restarts, and the summary carries `KDE Rice    applied (<sha>) — 'kderice restore' puts stock Breeze back`.

Then confirm idempotence — the property the whole script rests on:

```bash
./install.sh --only kderice
```

Expected: the same outcome with `· wallpapers already generated (153 slides)`, no regeneration, and no error.

- [ ] **Step 8: Commit**

```bash
git add install.sh tests/run.sh README.md
git commit -m "Install the KDE Rice launcher and apply the rice when the monitors match"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Ordering (last, after `configure_system`) | 2 (wiring), 3 (regression test) |
| Constants, clone-or-pull | 2, 3 |
| Dependencies in `pacman.txt` | 1 |
| Dependency guard for `--only kderice` | 3 |
| `build.py` always | 4 |
| Wallpapers only when missing, count via `tomllib` | 4 |
| Geometry gate via `check_geometry.py` on `build/wallpapers` | 5 |
| Empty `kscreen-doctor` output = gate failure | 5 |
| `setup` runs regardless of the gate | 6 |
| `apply` only when the gate passes | 6 |
| Warn + report on a gated rice | 6 |
| Never fatal | 3 (test), and every `return 0` path |
| Reporting, "Run them" list | 6 |
| README | 6 |
| Tests: `--only`, `--help`, dry-run inertness, step count | 2, 6 |

**Type consistency:** `kderice_expected_slides`, `kderice_have_slides`, `kderice_geometry_ok`, `kderice_deps` are each defined once (Tasks 4, 4, 5, 3) and called with matching arity in Tasks 4-6. `$dir` is the local alias for `$KDERICE_DIR` throughout `install_kderice()`. Task 5 writes the gate block and Task 6 edits that same block in place rather than adding a second one — called out in Task 6 Step 3, and asserted by Task 6's `kd_setup < kd_gate` ordering test, which fails if a duplicate gate ends up below `setup`.

**Out of scope** (per the spec): making `palette.toml` portable across monitor layouts, pinning the launcher in `packages/taskbar.txt`, and `kderice setup-login`.
