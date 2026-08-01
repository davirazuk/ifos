# IFOS

An Arch-based Linux distribution built for students at **IFMS — Campus Dourados**:
everything the technical courses need, plus the things you actually use a computer
for — games, music, and the rest.

> Unofficial student project. Not affiliated with, endorsed by, or produced by the
> Instituto Federal de Mato Grosso do Sul.

```
  ██╗███████╗ ██████╗ ███████╗
  ██║██╔════╝██╔═══██╗██╔════╝
  ██║█████╗  ██║   ██║███████╗
  ██║██╔══╝  ██║   ██║╚════██║
  ██║██║     ╚██████╔╝███████║
  ╚═╝╚═╝      ╚═════╝ ╚══════╝
```

* **Desktop** — i3 + polybar + rofi + picom in the IFMS green, JetBrains Mono
  Nerd Font. New windows open as **tabs**, not splits, so starting an app never
  rearranges what you already have open
* **Brazilian by default** — pt-BR locale, ABNT2 keyboard, America/Campo_Grande
* **Small ISO** — heavy applications are *not* shipped; `ifos-software` installs
  them on demand, from the official repos, the AUR or Flathub
* **Installer that keeps your data** — install alongside an existing system in
  free space, without reformatting anything

---

## Using the live medium

Boot it and you land straight in the desktop, logged in as **`ifos` / `ifos`**.
`Ctrl+Alt+F1` gets you a root console if you need one.

| Action | How |
| --- | --- |
| Install IFOS | `Mod+Shift+I`, or `sudo install-ifos` |
| Install applications | `Mod+Shift+A`, or `ifos-software` |
| Keyboard shortcuts | `Mod+F1` |
| Connect to Wi-Fi | tray applet, or `nmtui` |
| Make free space for a dual boot | GParted (installed) |

`Mod` is the Super / Windows key.

## Installing

```
sudo install-ifos
```

It asks for a keyboard layout, locale, timezone, hostname, username and password,
then how to use the disk. There are three disk modes:

| Mode | What it touches |
| --- | --- |
| **alongside** | Creates IFOS in unallocated free space and reuses the existing EFI partition. Nothing else is formatted, resized or removed — your other OS keeps working, and GRUB is configured with `os-prober` so it stays in the boot menu. |
| **partition** | Formats exactly the one partition you pick. |
| **wipe** | Erases the whole disk. Requires typing `ERASE`. |

Nothing is written until you type `YES` at the summary screen. The whole run is
logged to `/var/log/ifos-install.log`.

> **Before a dual-boot install:** shrink your existing partition with GParted
> first so there is unallocated space, and have a backup. Resizing a filesystem
> is the risky step, and IFOS deliberately does not do it for you.

`install-ifos --advanced` hands over to upstream `archinstall` with the IFOS
package set pre-filled, if you would rather drive that yourself.

## Installing applications

```
ifos-software
```

A menu of categories — Escola, Browsers, Gaming, Música, Development, Media,
Office, Utilities, Hardware. Pick what you want, it installs it.

The catalog is plain text in `airootfs/usr/share/ifos/apps.d/*.list`, one line
per entry:

```
Name|Description|package1 package2|source
```

`source` is `repo`, `multilib` (enables the multilib repository first), `aur`
(builds with yay) or `flatpak` (Flathub application id). Adding software to IFOS
means adding a line to a text file — no code involved.

## The launcher

`ifos-launcher` (or `Mod+G`) is a full-screen front end over the whole system —
big tiles, keyboard or gamepad navigation, one section per subject area. It
reads the same catalog as `ifos-software`, so installed applications launch and
missing ones offer to install themselves.

It also carries a built-in **Moodle front end**: the *Escola Online* section
embeds a browser pointed at the IFMS AVEA, with the academic system, SUAP, the
library and webmail one click away in the sidebar. That works on a fresh install
with no browser installed at all. The links live in
`airootfs/usr/share/ifos/escola.list` — plain text, edit freely.

Picking **IFOS Big Picture** at the login screen boots straight into it, console
style: the launcher *is* the session, and closing it ends the session.

## The shell

fish, configured as an IFOS environment rather than left at defaults: a
two-line prompt with git state and command timing, Catppuccin-derived colours on
the IFOS green, abbreviations that expand as you type (`gs`, `pu`, `..`), and
helpers — `extract`, `mkcd`, `up`. Everything is reachable through one command:

```
ifos              menu of everything
ifos apps         install software
ifos escola       Moodle and the IFMS systems
ifos jogos        games
ifos atalhos      keyboard shortcuts
```

Layout: `conf.d/ifos.fish` holds colours, abbreviations and aliases;
`functions/` holds the prompt and helpers. Both are yours to edit.

## Keeping it up to date

The IFOS parts of the system — the launcher, the catalog, the installer, the
themes, the login screen — live in this repository, so an installed machine can
pull them without reinstalling:

```
ifos-update              # update packages, then the IFOS files
ifos-update --check      # show what changed, change nothing
ifos-update --dotfiles   # also take the new desktop defaults (backs yours up)
ifos-update --ifos-only  # skip pacman
ifos-update --repair     # only repair known-broken files in your ~/.config
```

It clones the repo to `/var/lib/ifos/repo`, applies everything under
`airootfs/` with `branding-sync.sh`, and records the commit it applied so
`--check` can show you the difference. Your own `~/.config` is left alone
unless you pass `--dotfiles`.

### Fixes that have to reach a home directory you already have

Updating `/etc/skel` only changes what *new* accounts get; your existing
`~/.config` keeps whatever it was created with, bug and all. So `ifos-update`
also runs `/usr/share/ifos/repair-dotfiles.sh`, a list of narrow, idempotent
repairs to files you already have. They preserve the colours you are running —
only `--dotfiles` replaces your configuration outright.

```
/usr/share/ifos/repair-dotfiles.sh --check       # say what is broken
/usr/share/ifos/repair-dotfiles.sh               # repair this account
sudo /usr/share/ifos/repair-dotfiles.sh --all-users
```

On a machine installed before any of this existed, the update that brings the
repairs in is run by the *old* `ifos-update`, which does not know to call them.
That first time only, ask for them yourself:

```
ifos-update --ifos-only     # gets the new files, including the repair script
ifos-update --repair        # applies the repairs to your ~/.config
```

Point it at your own fork by editing `/etc/ifos/update.conf` — useful for
running a customised IFOS across a lab of machines.

> The repository has to be **public** (or the machine has to have credentials)
> for this to work.

## Other commands

| Command | Purpose |
| --- | --- |
| `ifos-launcher` | Full-screen launcher (`Mod+G`) |
| `ifos-update` | Update packages and pull the latest IFOS from GitHub |
| `ifos-theme ifms\|mocha\|toggle` | Switch between the green IFMS theme and Catppuccin Mocha; add `--system` to include the login screen, launcher and Big Picture session |
| `ifos-lock` | Lock the screen against the wallpaper (`Mod+L`) |
| `install-yay` | Enable AUR access |
| `ifos-post-install` | Re-apply IFOS defaults on an installed system |
| `/usr/share/ifos/repair-dotfiles.sh` | Repair known-broken files in a `~/.config` you already have |
| `ifos-welcome` | The welcome screen again |

---

## Building the ISO

You do **not** need Arch — the build runs in a rootless podman container.

```
./build.sh              # build into ./out
./build.sh --clean      # discard the work directory first
./build.sh --shell      # open a shell in the build container
```

Roughly 15 GB of scratch space, and a long first run while packages download.
Later builds reuse the pacman cache in `./work`.

Write the result to a USB stick:

```
sudo ./tools/flash-usb.sh --list      # find the stick
sudo ./tools/flash-usb.sh /dev/sdX    # write and verify it
```

It refuses to touch the disk holding `/` or `/home`, refuses non-removable
disks without `--force`, refuses a partition where a whole disk was meant, and
verifies the written bytes against the image afterwards rather than trusting
that `dd` succeeded.

Or try it without a USB stick:

```
qemu-system-x86_64 -m 4G -enable-kvm -cdrom out/ifos-*.iso
```

### Why a container

`mkarchiso` only runs on Arch. Two details make it work rootlessly:

* No user namespace may mount `devtmpfs`, which `pacstrap` does when it runs as
  root. mkarchiso avoids this by passing `pacstrap -N` — but only when it is
  *not* run as root, so the build runs as an unprivileged user in the container.
* That path needs `newuidmap`/`newgidmap`, which the upstream Arch container
  image ships without file capabilities, so the image grants them setuid instead.

Both are handled in `tools/Containerfile` and `tools/build-entrypoint.sh`.

### Repository layout

```
airootfs/            files copied into the live system
  etc/skel/          desktop dotfiles - also what a new user gets after install
  usr/local/bin/     install-ifos, ifos-software, ifos-welcome, ifos-theme
  usr/share/ifos/    software catalog, branding sync, keybinding help
packages.x86_64      what goes on the live medium
profiledef.sh        archiso profile settings and file permissions
build.sh             build entry point
tools/
  gen-artwork.py     regenerate wallpapers, login background and boot logo
  check-packages.sh  verify every package name still exists (build.sh runs it)
  fix-symlinks.sh    repair symlinks after a bad copy (build.sh runs it)
```

### ⚠️ Clone this repository, never "Download ZIP"

The profile depends on symlinks (`/etc/localtime`, the `systemd .wants`
directories, a `/dev/null` mask for a systemd generator). A ZIP download or a
`cp -rL` flattens every one of them into a copy of whatever the *host* had at
that path — which is exactly how this profile once ended up shipping Fedora unit
files inside an Arch ISO.

`build.sh` runs `tools/fix-symlinks.sh` first and repairs them automatically, so
a ZIP-based checkout still builds correctly — but cloning avoids the problem
entirely.

## Regenerating the artwork

```
python3 tools/gen-artwork.py                     # both themes, IFMS as default
python3 tools/gen-artwork.py --default-theme mocha
```

Produces the wallpapers, the SDDM login background and the Plymouth boot logo.

## Credits

Built on [archiso](https://gitlab.archlinux.org/archlinux/archiso). Colours from
[Catppuccin](https://github.com/catppuccin). Icons from
[Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).
