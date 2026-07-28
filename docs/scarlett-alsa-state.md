# Scarlett ALSA State

`alsa-scarlett-gui` settings for the Scarlett 4i4 4th Gen should normally persist in the interface hardware, but the upstream FAQ documents `alsa-state.service` and `alsa-restore.service` as a common cause of settings being overwritten from `/var/lib/alsa/asound.state` when the interface reconnects. The Arch audio setup masks those global ALSA state services and removes the global state file so they do not replay stale mixer controls over the hardware-stored configuration.

The user service `configure-scarlett-monitoring.service` owns workstation-specific Scarlett boot-time configuration. Its script first waits for ALSA card id `Gen`, then restores `~/.config/alsa-scarlett-gui/default.state` with `alsactl -f ... restore Gen` when that file exists; if no state file is present, it falls back to the narrow `amixer` direct-monitoring controls used before this convention.

To make a saved `alsa-scarlett-gui` `.state` persistent through dotfiles, store it at `for-my-eyes-only/dot-config/alsa-scarlett-gui/default.state`, stow the `audio` and `for-my-eyes-only` packages, and run the Arch audio setup tags so the service and global ALSA masking are installed. Do not store Scarlett boot policy in `/var/lib/alsa/asound.state`; that file is intentionally treated as disposable global system state.
Sandboxed assistant sessions may not see the active `~/.config/alsa-scarlett-gui/default.state` Stow target; verify the durable source at `for-my-eyes-only/dot-config/alsa-scarlett-gui/default.state` instead.
