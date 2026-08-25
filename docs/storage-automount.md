# Storage automount

`dev4` is an external ext4 drive (filesystem UUID `3dc52ee3-d7b3-4eb0-86aa-8237ca5c0ad7`, label `dev4`) that several borg backups, PKM takeouts, media bind mounts, and music-production bind mounts assume is mounted at `/run/media/<user>/dev4`. It used to be mounted by hand from the desktop file manager; now a udev rule plus a systemd one-shot mounts it on connect and at boot.

## How it works

- `playbooks/roles/10-system-tools/defaults/main/main.vars.yml` owns `arch_filesystem_automounts`, one entry per `(uuid, mountpoint, owner)`. Mountpoints follow the udisks2 `/run/media` layout so existing paths and tools keep working.
- Ansible renders `70-dotfiles-automount.rules` (under the role `templates/`) from that list. On `ACTION=="add"` for a matching `ID_FS_UUID` it sets `TAG+="systemd"` and `SYSTEMD_WANTS+=dotfiles-automount@<uuid>.service`. udev replays `add` for devices already present at boot, so the same rule covers both hotplug and boot.
- `dotfiles-automount@.service` (`assets/services/dotfiles-automount@.service`) runs `/usr/local/bin/dotfiles-automount <uuid>`. It is ordered `After=dotfiles-fs-label@%i.service`, so a relabel-triggered unmount can never race the mount.
- `assets/scripts/storage/dotfiles-automount` reads `/etc/dotfiles/automounts.conf` (`<uuid> <mountpoint> <owner>` per line), resolves the device with `blkid -U`, skips if already mounted, creates the mountpoint owned by the desktop user, and mounts with plain `mount(8)`. Running as root from the udev-spawned unit needs no udisks2/polkit session.

## Why not KDE or udisks2 automount

`peripherals/dot-config/kded5rc` disables Plasma's `device_automounter` module, and udisks2's own automount only runs inside an active desktop session. This drive should be up before and independently of the session so borg timers and the media/music-production bind mounts find it at boot. Unmounting stays manual (the nnn `nmount` plugin and the udisks2 polkit rule already handle that).

## Ownership and application

- Defaults: `arch_filesystem_automounts` in `10-system-tools/defaults/main/main.vars.yml`.
- Tasks: `playbooks/roles/10-system-tools/tasks/200-setup-file-manager-tools.archlinux.yml` (fs-label, automount, and udisks2 polkit setup live together there).
- Apply with `cd ~/dotfiles/playbooks && ansible-playbook tools.yml --tags 10-200`; changing a UUID or mountpoint needs that plus `sudo udevadm control --reload` to pick up the rule for already-present devices.

## MTP automount (Boox)

The Boox Note 3 e-reader is mounted with `jmtpfs` because Plasma's MTP KIO backend fails on it when USB debugging is on (`18d1:4ee2`, "MTP + ADB"). It appears in Dolphin as an unopenable `mtp://udi=...` entry; a dedicated jmtpfs mount sidesteps that entirely.

### How it works

- `arch_mtp_automounts` (same defaults file as `arch_filesystem_automounts`) owns one entry per `(serial, mountpoint, owner)`. Match is by USB serial (`5DEEF0C9`), which is stable across MTP/MTP+ADB mode switches even though `idProduct` flips between `18d1:4ee1` and `18d1:4ee2`.
- Ansible renders `70-dotfiles-mtp-automount.rules` (under the role `templates/`). On `ACTION=="add"` for a matching `ATTR{serial}` it clears `ID_MTP_DEVICE`/`ID_MEDIA_PLAYER` and sets `SYSTEMD_WANTS+=dotfiles-mtp-automount@<serial>.service`; on `ACTION=="remove"` it stops the service so the FUSE mount is torn down with the device.
- `dotfiles-mtp-automount@.service` (`assets/services/`) runs `/usr/local/bin/dotfiles-mtp-automount <serial>` as the desktop user (`User=`). jmtpfs stays in the foreground, so a service stop SIGTERMs it and libfuse unmounts.
- `assets/scripts/storage/dotfiles-mtp-automount` reads `/etc/dotfiles/mtp-automounts.conf` (`<serial> <mountpoint> <owner>` per line), skips when already mounted, creates the mountpoint, then `exec jmtpfs -f`.

### Why two workarounds

- Plasma's MTP daemon (`kmtpd`, loaded inside `kiod6` as a KDED module) opens every MTP device Solid reports as a `PortableMediaPlayer`, which makes jmtpfs fail with `libusb_claim_interface() ... device is busy`. Clearing `ID_MTP_DEVICE`/`ID_MEDIA_PLAYER` in the udev rule keeps Solid from flagging the Boox, so `kmtpd` never opens it. This is per-device (serial-matched), so other Android/MTP devices still show up in Dolphin.
- jmtpfs must run as the desktop user, not root. As root, libfuse 2.9.9's direct `mount(2)` path trips a fallback that passes `subtype=jmtpfs` to `fusermount`, which aborts with `fuse: unknown option '-osubtype=jmtpfs'`. Running as the user uses the normal fusermount path, and the files are owned by the user without `allow_other`.

### Usage and caveats

- Browse the device at `~/boox`; there is no `mtp://` entry for the Boox in Dolphin.
- jmtpfs mounts the first libmtp device it finds, so this assumes the Boox is the only MTP device connected at once.
- Calibre also claims the MTP interface, so keep it closed when the Boox is connected and mounted.
- `jmtpfs` is an AUR package published through the `aur-local` flow; it must be published before the `10-200` run can install it.

### Ownership and application

- Defaults: `arch_mtp_automounts` in `10-system-tools/defaults/main/main.vars.yml`.
- Tasks: `playbooks/roles/10-system-tools/tasks/200-setup-file-manager-tools.archlinux.yml`.
- Apply with `cd ~/dotfiles/playbooks && ansible-playbook tools.yml --tags 10-200`; a serial/mountpoint change also needs `sudo udevadm control --reload`.
