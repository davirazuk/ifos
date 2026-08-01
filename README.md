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
| Connect to Wi-Fi | click the Wi-Fi icon in the bar, or `nmtui` |
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

Because it now opens with the session, the first section is **Recentes** — what
this account last opened, most recent first. It appears once there is something
to put in it, and an application that has since been uninstalled drops off
rather than showing a tile that cannot start. The list lives in
`~/.config/ifos/recent`, outside `/etc/skel`, so it survives
`ifos-update --dotfiles`.

It also carries a built-in **Moodle front end**: the *Escola Online* section
embeds a browser pointed at the IFMS AVEA, with the academic system, SUAP, the
library and webmail one click away in the sidebar. That works on a fresh install
with no browser installed at all. The links live in
`airootfs/usr/share/ifos/escola.list` — plain text, edit freely.

Picking **IFOS Big Picture** at the login screen boots straight into it, console
style: the launcher *is* the session, and closing it ends the session.

## Old machines

IFOS is built for the machines a school actually has, so two things are set up
for them by default.

**Compressed swap.** `zram-generator` puts swap in RAM, compressed, sized to
half the memory and never more than 4 GiB. Swapping to a mechanical disk is the
difference between a computer that is slow and one that stops answering for
seconds at a time. The generator gives it swap priority 100 and a swap file
gets a far lower one, so the kernel fills zram first and only reaches the disk
once zram is full — the installer's swap file stays as the overflow. Configured
in `/etc/systemd/zram-generator.conf`; the compression algorithm is left at the
kernel default on purpose, because zstd costs more CPU per page and the CPU is
the scarce thing here.

**Power profiles.** Click the profile in the bar to move between power-saver,
balanced and performance.

## Graphics and games

The installer detects the graphics hardware and offers to install a driver for
it, rather than leaving that to a later trip through the software catalog. On a
machine with an NVIDIA card it offers the open kernel module branch, and says
plainly that a card older than a GTX 16-series needs nouveau instead. On a
hybrid laptop it adds `nvidia-prime`, so `prime-run <game>` sends a game to the
discrete chip — without it every game quietly runs on the integrated one and
the machine just seems slow.

Choosing a driver also enables the multilib repository on the installed system.
The 32-bit libraries games need can only be installed with it on, and a system
that received them without it would never be able to update them again.

`vm.max_map_count` is raised in `/etc/sysctl.d/99-ifos.conf`. The kernel default
is far below what modern games need through Proton and DXVK, and a title that
runs past it does not warn — it fails to start, or crashes partway in with
nothing in its own logs to explain why.

Steam, Lutris, Heroic, Wine, Proton-GE, MangoHud, GameMode and Gamescope are all
one line in `ifos-software`.

## The bar

The status bar is where the machine is actually driven from, so the things
people reach for most are a single click away rather than behind a settings
application:

| Click | What happens |
| --- | --- |
| Wi-Fi icon | Networks in range; Enter joins, and it asks for a password only when it needs one. Right-click for the connection editor |
| Bluetooth icon | Paired devices; Enter connects. Right-click for blueman, which handles pairing something new |
| Power profile | Cycles power-saver / balanced / performance, showing which is active |
| Now playing | Play and pause; the scroll wheel skips. Absent entirely when nothing is playing |
| Battery, volume, CPU, memory | Status at a glance |

`Mod + Esc` opens a graphical task manager — processes plus CPU, memory and
network graphs — for when `htop` is not what you want.

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
ifos-update                 # packages, IFOS files, your desktop, then restart
ifos-update --check         # show what would change, change nothing
ifos-update --no-reboot     # everything, but stay running
ifos-update --no-dotfiles   # leave your own ~/.config alone
ifos-update --ifos-only     # skip pacman
ifos-update --repair        # only repair known-broken files in your ~/.config
```

One command brings a machine fully current. It clones the repo to
`/var/lib/ifos/repo`, applies everything under `airootfs/` with
`branding-sync.sh`, records the commit it applied so `--check` can show you the
difference, refreshes your `~/.config` from the new defaults, and restarts.

The desktop refresh and the restart are both part of the normal run rather than
flags to remember. Changing `/etc/skel` does not reach a home directory that
already exists, so leaving it opt-in meant half of an update quietly did not
arrive; and most of what an update lands — a new kernel, the boot menu, the
input configuration, the login screen, the files the running session already
read — only takes effect on a fresh boot. Your previous configuration is copied
to `~/.config-backup-<date>` first (the three most recent are kept), and the
restart is a countdown you can cancel with Ctrl+C.

### Fixes that have to reach a home directory you already have

Updating `/etc/skel` only changes what *new* accounts get; your existing
`~/.config` keeps whatever it was created with, bug and all. So `ifos-update`
also runs `/usr/share/ifos/repair-dotfiles.sh`, a list of narrow, idempotent
repairs to files you already have. They preserve the colours you are running,
and they are what `--no-dotfiles` leaves you with when you would rather keep
your own configuration than take the new defaults.

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
| `ifos-update` | Update packages, IFOS files and your desktop, then restart |
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
