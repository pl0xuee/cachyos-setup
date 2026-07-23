# CachyOS post-install setup

On a fresh box, log into KDE once, then:

```bash
curl -fsSL https://raw.githubusercontent.com/pl0xuee/cachyos-setup/master/bootstrap.sh | bash
```

Safe to re-run — a second run is a no-op.

```bash
./install.sh --dry-run          # show what it would do, change nothing
./install.sh --only config      # just the KDE/Brave config
./tests/run.sh                  # 157 tests, no VM needed
```

**Log into KDE before running it.** Plasma doesn't write its panel config until
first login, so the desktop step has nothing to configure before then.

**Close Brave and KeePassXC first.** Both rewrite their own config on exit and
will silently undo the changes.

## What goes where

| File | |
|---|---|
| `packages/pacman.txt` | repo packages (no AUR) |
| `packages/flatpak.txt` | Dropbox |
| `packages/taskbar.txt` | pinned launchers, in order |
| `packages/brave-extensions.txt` | extensions to auto-install |
| `install.sh` | panel height, tray, homepage, power profile — as variables at the top |
