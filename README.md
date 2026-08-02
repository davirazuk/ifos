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
| **wipe** | Erases the whole disk. Requires typing `APAGAR`. |

Nothing is written until you type `SIM` at the summary screen. The installer
asks its questions in Portuguese. The whole run is
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

Sections run down a sidebar on the left, each with the icon its catalog file
names, and the one you are in is spelled out above the tiles. They used to be a
strip across the top, which scrolled once there were more than a few — the later
sections sat off the edge, reachable only by dragging something that did not
look draggable. Down the side a dozen of them fit on a 1366×768 laptop screen
with room to spare. Typing searches the whole machine, not just the open
section; `Tab` moves to the next section, `Esc` leaves.

Search is written for the people using it. Accents are ignored on both sides,
so `musica` finds *Música* and `programacao` finds *Programação* — typing the
accents is possible on the ABNT2 keyboard IFOS ships and nobody does it inside
a search box. It also knows the names people arrive already knowing: `photoshop`
finds GIMP and Krita, `word` and `excel` find LibreOffice, `winrar` finds Ark,
`premiere` finds Kdenlive. Those live in `SEARCH_ALIASES` near the top of
`ifos-launcher` and are a search aid, not a claim that the programs are
equivalent. Section names work too — `jogos` lists the games. A search that
matches nothing says so and suggests what else to try, rather than leaving a
blank page that looks like a crash.

Because it now opens with the session, the first section is **Recentes** — what
this account last opened, most recent first. It appears once there is something
to put in it, and an application that has since been uninstalled drops off
rather than showing a tile that cannot start. The list lives in
`~/.config/ifos/recent`, outside `/etc/skel`, so it survives
`ifos-update --dotfiles`.

It also carries a built-in **Moodle front end**: the *Escola Online* section
embeds a browser pointed at the IFMS AVEA, with the academic system, SUAP, the
library and webmail a click away along the top, or `←`/`→` from the keyboard.
That works on a fresh install with no browser installed at all, and *Abrir no
navegador* hands the current page to a real browser once one is installed. The
links live in `airootfs/usr/share/ifos/escola.list` — plain text, edit freely.

Picking **IFOS Big Picture** at the login screen boots straight into it, console
style: the launcher *is* the session, and closing it ends the session.

## Whatever screen the machine has

Two things used to be assumed and are now detected.

**Density.** A laptop with a 3200x1800 or 4K panel — an ordinary second-hand
machine now, not an exotic one — got a 32-pixel bar about four millimetres
tall, text at a third of its intended size, and a cursor you could lose, with
nothing in the interface to fix it with. `ifos-scale` reads the panel's size
out of EDID at login and sets the font DPI, the widget scale, the cursor size
and the bar's height and DPI to match. Below 120 dpi it sets exactly the values
that used to be hardcoded, so on the machines in the lab nothing changes at
all. An EDID that reports 0mm — which projectors routinely do, and some laptop
panels — is ignored in favour of the pixel count. Run `ifos-scale` on its own
to see what it decided.

**Screens.** Plugging a projector in did nothing: X saw the output, i3 did not
configure it, and the second screen stayed dark. `autorandr` now notices the
change and lays the screens out side by side, without anyone having saved a
profile for that room's projector first, and polybar puts a bar on each one.
`Mod+P` re-runs the detection by hand for a dock that presents its output late
or a cable swapped mid-class.

## Old machines

IFOS is built for the machines a school actually has, and what the machine gets
is measured rather than assumed. `ifos-scale --machine` prints
every decision in one place — memory, cores, whether there is a working GPU,
the screen's density, and what the desktop did with each. The rule throughout
is that adapting may only ever make a machine do *less* work than the default,
never more: the worst case of guessing wrong is a plainer desktop, not a slower
one.

| the machine has | what changes |
| --- | --- |
| no GPU render node | picom uses the software backend, no animations |
| under 3.5 GiB RAM, or fewer than 4 cores | still composited — rounded corners, shadows, fading — but windows do not animate. `IFOS_PICOM_ANIMATIONS=1` overrides |
| a small disk | the swap file default is capped at a tenth of the root partition; below 1 GiB there is none, since zram covers it |
| a high-density screen | fonts, widgets, cursor and bar scale — see *Whatever screen the machine has* |

Two things used to grow to fill whatever disk they were given, on every
machine. systemd sizes the journal at 10% of the filesystem — about 3 GiB on a
32 GiB eMMC laptop — and `paccache` keeps three versions of every package it
has ever downloaded, which on a rolling release is the largest thing on the
disk after a few months. The journal is capped at 200 MiB and the cache keeps
one version, with uninstalled packages dropped entirely.

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
hybrid laptop it adds `nvidia-prime`, which is what lets a game reach the
discrete chip at all.

The same step installs the firmware a machine needs to keep working after the
install. Several things were on the live medium and not in the installed
system, which produces the worst kind of bug report — *it worked before I
installed it*: `sof-firmware`, without which Intel laptops from about 2019 on
have no audio at all; the Wi-Fi regulatory database, without which the 5 GHz
network may simply not appear; and, only on machines that actually have the
chip, the Broadcom wireless driver, without which those laptops finish the
install with no Wi-Fi.

Choosing a driver also enables the multilib repository on the installed system.
The 32-bit libraries games need can only be installed with it on, and a system
that received them without it would never be able to update them again.

`vm.max_map_count` is raised in `/etc/sysctl.d/99-ifos.conf`. The kernel default
is far below what modern games need through Proton and DXVK, and a title that
runs past it does not warn — it fails to start, or crashes partway in with
nothing in its own logs to explain why.

**On a laptop with two graphics chips, games use the fast one on their own.**
Everything renders on the integrated chip by default, which is what makes the
battery last and is wrong for exactly one kind of program — so the launcher
sends games to the discrete card and leaves everything else alone. It knows
which entries are games because the catalog already sorts them, and it also
honours `PrefersNonDefaultGPU`, the desktop-entry key Steam and Lutris set on
the shortcuts they generate. Nobody has to know the word `prime-run`, and
nobody has to discover months later that their machine had been running
everything on the slow chip.

`ifos-gpu` shows what the machine has, for the rare case of starting something
heavy from outside the launcher.

**When the graphics break, something says so and offers to fix it.** A graphics
driver that goes missing does not announce itself: X falls back to drawing on
the processor, everything still appears, and the only symptom is that the
machine is slow and Steam refuses to open with a message about `libGL`.
Diagnosing that took `lsmod`, `modinfo` and `glxinfo`, which is not a
reasonable thing to ask of a first-year student.

`ifos-gpu --check` names the problem in Portuguese and `ifos-gpu --fix` repairs
it; the launcher has it as **Vídeo e jogos** under Sistema, so no terminal is
involved. It covers NVIDIA, AMD and Intel and every hybrid combination, and it
knows the specific ways this actually fails:

| What is wrong | What it says |
| --- | --- |
| multilib switched off | Steam's 32-bit libraries cannot even be installed — offers to enable it |
| `lib32-*` missing | the exact packages Steam needs |
| No NVIDIA module for the running kernel | names the kernel; rebuilds through DKMS |
| Prebuilt driver on a machine with two kernels | swaps it for the DKMS one, which follows both |
| nouveau holding the card | blacklists it and regenerates the initramfs |
| Driver updated, machine not rebooted | says so, instead of looking like a broken install |
| `nvidia_drm` without modeset | the cause of flicker and black screens after suspend |
| Rendering on the CPU | the verdict, with the renderer it found |

An old NVIDIA card running nouveau is reported as correct rather than as a
fault: nouveau is the right driver for a GTX 750, and nobody gets pushed onto
one that does not support their hardware.

`tools/test-tools.sh` runs the doctor against fourteen machines that do not
exist — a hybrid laptop booted on the LTS kernel with a driver built for the
other one, an AMD desktop with no multilib, a card that predates the open
modules — because none of those can be reproduced on the machine IFOS is built
on, and each one is a student in front of a computer that will not open Steam.

**Jogos lists the games you have, not just the ones you could install.** The
section used to be a shop — Steam, Lutris, Heroic, Wine — with no way to reach
a game from it; every installed game sat in "Todos" between LibreOffice Calc
and the printer settings. A game says so itself, in the `Game` category of its
desktop entry, which Steam, Lutris and Heroic all write into the shortcuts they
generate, so the list is whatever the machine has rather than something anyone
maintains. Installed games come first, the catalog after them, and each one
still goes to the discrete card on its own.

The Big Picture session opens straight there, which is the difference between a
console and a catalogue when the machine is across the room with a gamepad.

**Controllers work as controllers, not as generic pads.** A DualSense on a
fresh Arch install half works, and the missing half is invisible: the kernel
driver claims it, so the buttons do something, but SDL — which is what almost
every game and emulator actually reads — also wants `/dev/hidraw*` for the
parts that are not buttons. Rumble, the gyroscope, the light bar, the adaptive
triggers, and the report saying *which* controller this is so the game can draw
the right prompts. `/dev/hidraw*` is root-only and nothing tags it, so the pad
ends up nameless, silent, with PlayStation buttons labelled A/B/X/Y.

`/etc/udev/rules.d/70-ifos-game-controllers.rules` tags it, for PlayStation,
Nintendo, Xbox, 8BitDo and Valve hardware. Steam ships rules of its own that
cover much of this; these exist so a machine without Steam — an emulator, a
Godot project, the launcher's own gamepad support — behaves the same way.

`ifos-controller` says which controllers are connected, whether this account can
actually reach them, and how to put each family into Bluetooth pairing mode —
because "o controle não funciona" is three different problems that look
identical from the sofa. `ifos-controller --test` prints buttons and sticks as
you press them. It is **Controles** under Sistema in the launcher.

**The catalog's AUR names are checked too, now.** `check-packages.sh` resolved
the `repo` and `multilib` entries against a synced database and skipped the
`aur` ones — so a catalog entry naming a package that is not in the AUR at all
shipped, and the first anyone knew was a student watching yay say `no package
found for targets` and give up. The names cannot be checked from a machine
without access to the AUR, so the check runs in the build container that
already has it, against the AUR's own API. Thirty catalog entries had never
been verified by anything.

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
| Bell | Everything the machine said and you did not catch, plus Não perturbe. Right-click silences without opening anything |

The bar is flat: coloured icons and dim text straight on the background, with
no box around each module. Two attempts at giving the modules a filled
background — first squares, then rounded pills — both made it worse and were
taken back out. The launcher button keeps a filled background because it is a
button rather than a readout.

`tools/check-icons.py` reads the bar config as modules rather than as one file,
because which modules must carry an icon is a property of the module: a
`custom/script` prints its own and the config never mentions one, while every
other module has the icon written in the config.

**A notification that times out is gone.** Everything the machine has to say —
the battery warning, the disk warning, the graphics check, "reinicie depois de
instalar o driver" — appeared for eight seconds in a corner and then existed
nowhere. Someone looking away, or typing, or in a game, never saw it.

The bell in the bar keeps the count and `Mod + Shift + N` opens the history:
every notification still kept, newest first, with the application and how long
ago it arrived. Picking one shows it again *with its buttons* — the graphics
check sends a notification whose action opens the repair, and that action
survives the notification timing out. Left-clicking a notification now runs its
action before closing, which is what "clique aqui para consertar" always
implied and never did; it was on middle click, where nobody would find it.

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
