# CachyOS post-install setup

Gets a fresh CachyOS box back to my setup in one command.

CachyOS already ships a full KDE desktop, so this deliberately does **not**
re-list the base system. It only installs the *delta*: the apps that aren't on
the ISO, two of my own programs that aren't packaged anywhere, and the desktop
config to match.

## Run it

```bash
curl -fsSL https://raw.githubusercontent.com/pl0xuee/cachyos-setup/master/bootstrap.sh | bash
```

That clones the repo and runs the installer. It has to clone rather than pipe
`install.sh` straight in, because the script reads its package lists from
`packages/*.txt`.

**Log into the KDE desktop first.** Plasma only writes its panel config at first
login, so the desktop step has nothing to configure before then.

### Or, the version where you read it first

Piping a URL into `bash` runs whatever happens to be at that URL. Reasonable
people don't do that. The honest way:

```bash
git clone https://github.com/pl0xuee/cachyos-setup.git
cd cachyos-setup
less install.sh              # see what you're about to run
./install.sh --dry-run       # every command it would run, changing nothing
./install.sh                 # do it
```

Re-running is safe — every step is idempotent, and a second run is a no-op.

## What it installs

**Repo packages** (`packages/pacman.txt`) — Vesktop, Brave, KeePassXC, GNOME
Disks, LACT, the CachyOS gaming stack (the same thing the "Install Gaming
packages" button in CachyOS Hello installs), and the build toolchain the two
custom apps need.

**Flatpak** (`packages/flatpak.txt`) — Dropbox. Only used for things the repos
don't carry.

**[AgentTileCLI](https://github.com/pl0xuee/agenttilecli)** — cloned and built
from source (Rust + GTK4/VTE4).

**[StreamHub](https://github.com/pl0xuee/StreamHub)** — the prebuilt AppImage
from GitHub Releases. Not built from source: the release bundles castLabs
Electron, which is what makes Widevine playback work.

## No AUR

Everything comes from the official Arch and CachyOS repos. CachyOS packages a
lot of what would otherwise be AUR-only (`brave-origin-bin`, `vesktop`), so
nothing here needs an AUR helper.

If you add a package that turns out to be AUR-only, the script will fail on it
rather than quietly pulling in `paru` — prefer a Flatpak instead.

## Adding packages

Edit the lists in `packages/`. One name per line; `#` comments and blank lines
are ignored. Check a package is in the repos first:

```bash
pacman -Si <name>          # found → add to pacman.txt
flatpak search <name>      # otherwise try Flathub → flatpak.txt
```

`packages/pacman.txt` also has a commented-out "optional extras" block
(Chromium, GitHub CLI, Xvfb, IceWM) — uncomment what you want.

## Options

| Flag | Effect |
|---|---|
| `--dry-run` | Print every command, change nothing |
| `--only STEP` | Run one step: `packages`, `flatpak`, `agenttilecli`, `streamhub`, `config` |
| `--skip-upgrade` | Skip the initial `pacman -Syu` |

The full system upgrade runs first by default and you should leave it that way.
Installing against a stale package database is a *partial upgrade*, which is
the classic way to break an Arch system.

`PROJECTS_DIR` sets where AgentTileCLI is cloned (default
`~/Documents/Projects`). It needs to be somewhere permanent — the app's built-in
updater pulls and rebuilds from that same clone.

## The desktop

The `config` step reproduces the KDE setup:

- **Taskbar launchers** (`packages/taskbar.txt`), in order:
  Brave · Vesktop · Steam · KeePassXC · Dolphin · AgentTileCLI · StreamHub
- **Panel height** 40px (Plasma's default is 30)
- **"Peek at Desktop" removed** from the panel
- **Tray items hidden** behind the expander: brightness, clipboard, battery,
  keyboard indicator

Reordering `taskbar.txt` reorders the taskbar. Anything listed that isn't
installed is skipped with a warning rather than left as a dead tile.

One caveat: **log into the KDE desktop once before running this.** Plasma creates
the applet config at first login, and there's nothing to configure until it
exists. If you run the script before that, it says so and skips the step — re-run
`./install.sh --only config` afterwards.

## Brave

Configured through Chromium enterprise policy in `/etc/brave/policies/managed/`
(the path is compiled into the `brave-origin` binary — verified, it works):

- **Extensions auto-install** on first launch (`packages/brave-extensions.txt`):
  KeePassXC-Browser, Plasma Integration, BigTube, New Netflix 1080p.
  They install as `normal_installed`, not `force_installed` — so you can still
  disable or remove them. Force-installed extensions can't be removed at all,
  not even by you.
- **Homepage and new tab** → `pl0xuee.com`. Being policy, Brave shows these as
  "managed by your organisation" and greys them out in Settings. To change one,
  edit `BRAVE_HOMEPAGE` in `install.sh` and re-run.
- **Experimental ad-block filter list** enabled. This one is *not* policy —
  filter lists live in Brave's own `Local State` file, so the script seeds it
  there by UUID. It merges rather than overwrites, so it's safe on an existing
  profile.

**KeePassXC ↔ Brave Origin** needs a manual step that the script does for you.
KeePassXC's "Brave" checkbox writes its native-messaging manifest to
`~/.config/BraveSoftware/Brave-Browser/` — the path *upstream* Brave uses. Brave
Origin reads `Brave-Origin/`, so ticking that box achieves nothing. The script
writes the manifest to the right place.

Close Brave and KeePassXC before running the config step: both rewrite their own
config on exit and will silently undo these changes otherwise. The script warns
you if it spots either running.

## Afterwards

Nothing. That's the point — the script finishes the job.

It enables the `lactd` daemon (LACT can't talk to the GPU without it), puts
`~/.local/bin` on your PATH for fish, bash and zsh so `agenttilecli` and
`StreamHub` run by name, and pins the taskbar. Open a new shell and everything
works.

## What it does with elevated privileges

This script uses `sudo`. Read it before you run it — that goes for any script
that asks for your password. Specifically, it:

- runs `pacman -Syu` and installs the packages in `packages/pacman.txt`
- installs the Dropbox Flatpak **as root** (system scope). An unprivileged
  `flatpak install` needs polkit, which can't prompt in a non-interactive run.
- writes `/etc/brave/policies/managed/extensions.json` (Brave's managed policy)
- enables the `lactd` and `power-profiles-daemon` system services

Everything else stays in your home directory.

**Things it fetches from the internet:**

| Source | What |
|---|---|
| Arch / CachyOS repos | packages, signed and verified by pacman |
| Flathub | Dropbox |
| `github.com/pl0xuee/agenttilecli` | cloned and built from source |
| `github.com/pl0xuee/StreamHub` | release AppImage — **sha512-verified** against the release's `latest-linux.yml` before it's made executable |
| `claude.ai/install.sh` | piped to bash, Anthropic's official installer. AgentTileCLI runs `claude` in every pane and is useless without it. If you'd rather not, comment out `ensure_claude_cli`. |
| Chrome Web Store | the four Brave extensions, via policy |

The StreamHub AppImage is the one binary here that gets downloaded and executed
directly, so its checksum is checked and a mismatch aborts the install rather
than warning. Failing to *fetch* the checksum also aborts — "couldn't verify"
isn't "verified".

## Tests

```bash
./tests/run.sh
```

Runs locally, installs nothing, needs no VM. Checks argument handling, the
package-list parser, that every package name still resolves in an enabled repo,
that the StreamHub release asset still exists and is still unversioned (its
in-app updater breaks if it ever gains a version in the filename), that the
generated `.desktop` file passes `desktop-file-validate`, and that `--dry-run`
really does touch nothing.

## Verified against a real fresh install

There's a CachyOS VM in `~/VMs/cachyos-test` with a `pristine` snapshot of a
clean install (sshd + key + passwordless sudo already set up, so it can be
driven headlessly):

```bash
cd ~/VMs/cachyos-test
./test-run.sh     # reset to pristine, boot, copy the repo in, run install.sh
./vm.sh reset     # back to a fresh install in ~1 second
./vm.sh run       # boot with a window
./vm.sh ssh       # shell into the guest
```

This script has been run end to end against that guest: full upgrade, all 17
packages (including the ~5.4 GB gaming stack), the Dropbox flatpak, the
AgentTileCLI cargo build, and the StreamHub AppImage — then re-run to confirm
it's a genuine no-op the second time.

**Do not infer the stock baseline from this machine's `pacman.log`.** It's
misleading: Vesktop, Brave, KeePassXC, LACT and GNOME Disks have no "installed"
entry, which makes them look like they ship with the ISO. They don't — they
exist in the live ISO's session but Calamares never writes them to disk. Nor
does a fresh install have `flatpak`, any Flatpak remote, or `~/.local/bin` on
`$PATH`. Check the VM, not this box.
