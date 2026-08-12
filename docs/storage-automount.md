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
