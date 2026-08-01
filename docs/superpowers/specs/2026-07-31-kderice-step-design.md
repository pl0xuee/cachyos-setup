# Design: install and apply the KDE rice from install.sh

Add [`pl0xuee/kderice`](https://github.com/pl0xuee/kderice) — "Gunmetal Filament",
a reversible KDE Plasma 6.7 rice — as a step in `install.sh`, and apply it as part
of a normal run.

## Why it needs a design at all

kderice is not another AppImage. Three things make it different from every other
step in this script:

1. **It is machine-specific by construction.** `palette.toml` declares three
   outputs by name, resolution, scale and Plasma *containment id* — `DP-1`
   3440x1440 / c43, `DP-2` 3840x2160 @1.5 / c44, `DP-3` 1440x2560 portrait / c45.
   Those are the ids Plasma assigned on one particular machine. A fresh box with
   a single 1080p monitor matches none of it.
2. **Applying is expensive up front.** `kderice apply` refuses to run until the
   wallpapers exist, and generating them is ~90s on 16 cores and ~590 MB.
3. **It shares files with this script.** `install.sh` owns the panel's applet
   list; kderice owns the panel's appearance. The two touch the same
   `appletsrc` and both stop plasmashell to do it.

## Ordering

`install_kderice` runs **last**, after `configure_system`.

This is forced, not preferred. `configure_taskbar` rewrites `appletsrc`
(launchers, `AppletOrder`, `hiddenItems`) and restarts plasmashell. kderice's
README states the contract from the other side: the two tools own disjoint keys,
and after re-provisioning you re-run `kderice apply`. Running the rice first
would take its snapshot against a panel that `configure_taskbar` is about to
rewrite.

## The step

### Constants

```bash
KDERICE_REPO="https://github.com/pl0xuee/kderice.git"
KDERICE_DIR="$PROJECTS_DIR/kderice"
```

A sibling of the agenttilecli clone, which is what kderice's own README assumes
(it refers to `../agenttilecli`). Like agenttilecli, this is a permanent path:
the rice is re-applied from this clone, not from a temp dir.

### Clone or pull

Identical to `install_agenttilecli`: `git clone` when absent, `git pull
--ff-only` when present, and on a refused fast-forward warn and build what is
already there rather than clobbering local work.

### Dependencies

New section in `packages/pacman.txt`:

| package | why |
|---|---|
| `python-numpy` | `generate/wallpaper.py` |
| `python-pillow` | `generate/wallpaper.py` |
| `ttf-fira-mono` | `kderice apply` hard-fails without it; pre-installing means `kderice setup` never fires its own sudo prompt |
| `qt6-imageformats` | Qt reads the lossless WebP slides through this |
| `kscreen` | `kscreen-doctor`, which feeds the geometry gate |
| `rsync` | `kderice apply` installs the wallpapers with it |

`--only kderice` can reach the step without the packages step having run, so the
step guards its own dependencies and installs what is missing — the precedent is
the `minisign` guard in `verify_griddown`. Concretely, it probes
`python3 -c 'import numpy, PIL'` and `have rsync kscreen-doctor`, and checks the
font with `fc-match --format='%{file}' "Fira Mono"`. Anything missing is
installed with a single `sudo pacman -S --needed --noconfirm`; if that fails,
warn and skip the step rather than proceed into a `die` inside `kderice`.

### Sequence

1. `python3 generate/build.py` — cheap, always runs. Asserts WCAG contrast, so a
   bad palette edit fails here rather than on screen.
2. **Wallpapers, only when missing.** The expected slide count is
   `variants x len(sizes)`, read out of `palette.toml` with a one-line
   `python3 -c` using `tomllib` — not parsed in bash, which cannot read TOML and
   would go stale the moment the file grows a comment shaped like a key. Compare
   it against `find build/wallpapers -mindepth 2 -type f -name '*.<format>' | wc -l`,
   where `<format>` also comes from `palette.toml`. Equal means skip; anything
   less means run `generate/wallpaper.py`. This is what keeps a re-run of
   `install.sh` a near no-op, which is the promise its README already makes.
3. **Geometry gate.**
   ```bash
   kscreen-doctor -j | python3 "$KDERICE_DIR/generate/check_geometry.py" \
       "$KDERICE_DIR/build/wallpapers"
   ```
   kderice's own checker, pointed at `build/wallpapers` instead of its default
   `~/.local/share/wallpapers/gunmetal` so it can run *before* apply has
   installed anything. It compares every declared output against the live
   geometry — name present, resolution, scale, and the priority-to-containment
   mapping — and checks that each resolution folder holds slides of that
   resolution. Exit non-zero means this box is not the one `palette.toml`
   describes.
4. `./bin/kderice setup` — links `kderice` and `kderice-launch` into
   `~/.local/bin` and installs the KDE Rice launcher entry and icon. **Runs
   regardless of the gate**, so a mismatched box still gets the toggle and can be
   riced by hand after fixing `palette.toml`.
5. `kderice apply` — **only when the gate passed.**

### When the gate fails

Warn, and record a report line carrying `check_geometry.py`'s own output (it
already prints one line per output naming exactly what differs, and a closing
"fix palette.toml [wallpaper].sizes, then: ..." hint). Do not apply. The desktop
is left stock, the launcher is installed, and the user has the diagnosis.

If `kscreen-doctor` is absent, or produces empty output, treat that as a gate
failure too, not a pass. `check_geometry.py` returns 0 on empty input — right for
a status command, wrong for a gate. So the step tests the captured JSON for
non-emptiness itself before piping it in, and skips apply with its own warning
when there is nothing to check against.

### Cost of the gate ordering — accepted tradeoff

On a mismatched box the ~90s and ~590 MB of wallpaper generation is spent
*before* the gate can speak, because `check_geometry.py` cannot verify slide
resolutions until slides exist. The alternative is duplicating its comparison
logic in bash inside `install.sh`, which would drift from the real checker.

Accepted: `build/` is documented as safe to delete, `install.sh` already builds
Rust from source and downloads several hundred MB of AppImages, and a user who
fixes `palette.toml` has to regenerate anyway.

### Failure is not fatal

The step warns and reports rather than aborting the run — the precedent is
`install_discripper`. `configure_system` has already completed by the time this
runs; a rice that failed to apply should not cost the user the rest of a working
setup.

## Reporting

- `report "KDE Rice" "..."` lines in the same style as the other steps: the
  commit that was built, whether wallpapers were generated or reused, and
  whether the rice was applied or gated.
- `main()`'s closing "Run them" list gains `kderice` — toggle the desktop rice.

## Docs

`README.md` gains a `packages/` note for the new dependencies and a line stating
that the rice is built and applied at the end of a run, with `kderice restore`
named as the way back to stock.

## Tests

`tests/run.sh` gets the coverage every other step already has:

- `--only kderice` is accepted
- the `--only` rejection message names `kderice` among the valid steps
- `--help` documents the step
- `--dry-run` reaches the step and still changes nothing (no clone, no build)
- the step-count arithmetic is right (`STEP_TOTAL` 13 -> 14, and 2 under `--only`)

The rice's own behaviour is out of scope here — kderice ships `tests/sandbox.sh`,
which proves snapshot/restore against a throwaway `HOME`.

## Out of scope

- Editing `palette.toml` to make the rice portable across monitor layouts. The
  gate detects the mismatch and says so; generalising the rice is kderice's
  problem, not this script's.
- Pinning the KDE Rice launcher in `packages/taskbar.txt`. It is designed as an
  app-menu toggle, and `taskbar.txt` is for everyday apps.
- `kderice setup-login`. It only opens a settings page for a human to click, and
  theming the greeter needs root for no benefit this script can automate.
