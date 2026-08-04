# CachyOS post-install setup

On a fresh box, log into KDE once, then:

```bash
curl -fsSL https://raw.githubusercontent.com/pl0xuee/cachyos-setup/master/bootstrap.sh | bash
```

Safe to re-run — a second run is a no-op.

```bash
./install.sh --dry-run          # show what it would do, change nothing
./install.sh --only config      # just the KDE/Brave config
./tests/run.sh                  # 284 tests, no VM needed
```

**Log into KDE before running it.** Plasma doesn't write its panel config until
first login, so the desktop step has nothing to configure before then.

**Close Brave and KeePassXC first.** Both rewrite their own config on exit and
will silently undo the changes.

**The desktop rice is applied last.** `install.sh` clones
[kderice](https://github.com/pl0xuee/kderice) and applies it after the panel is
configured — plasmashell restarts, so the desktop flickers once. `kderice
restore` puts stock Breeze back, and the **KDE Rice** entry in the app launcher
toggles between them. On a machine whose monitors don't match kderice's
`palette.toml`, the rice is built and the launcher installed but nothing is
applied, and the run says so.

## What goes where

| File | |
|---|---|
| `packages/pacman.txt` | repo packages (no AUR) |
| `packages/flatpak.txt` | Dropbox |
| `packages/taskbar.txt` | pinned launchers, in order |
| `packages/brave-extensions.txt` | extensions to auto-install |
| `install.sh` | panel height, tray, homepage, power profile — as variables at the top |
| `~/Documents/Projects/kderice` | the KDE rice — cloned, built and applied at the end |
