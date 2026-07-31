# Superseded setup scripts

These two scripts built the first version of the IFOS profile by mutating it in
place. They are kept for history; **do not run them again.**

They are not idempotent. Running `setup_ifos2.sh` three times is what left the
profile with the Qt environment exported three times in `.bashrc`, three copies
of the polybar autostart line in the i3 config, and the same in the fish config.
`setup_ifos.sh` also deleted the filesystem tools (`dosfstools`, `e2fsprogs`,
`btrfs-progs`, ...) that the installer needs to format a disk.

The profile itself is now the source of truth. Edit the files under `airootfs/`
directly and build with `./build.sh`.
