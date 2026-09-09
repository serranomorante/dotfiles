# Repository Map

Use this file to choose the source file that owns a behavior before editing generated or active-system paths.

## Top Level

- `playbooks/`: Ansible entrypoints, roles, templates, filters, modules.
- `peripherals/`: keyd, mouseless, warpd, tablet/display helpers, keyboard-driven desktop actions.
- `nvim/`: Neovim config, wrappers, plugin/job/session integration.
- `term/`: Kitty, tmux, terminal wrappers, quick-access TUIs.
- `systemd/`: generic user units not owned by a narrower package.
- `audio/`: audio/MIDI production tooling, Bluetooth helpers, pedalboard actions.
- `mypaint/`: MyPaint settings, custom brushes, brush order under `dot-config/mypaint/` and `dot-local/share/mypaint/`.
- `utilities/`: general scripts/config, health tooling, notification actions, browser/task helpers, KDE runtime config.
- `PKM/`: public PKM tooling; private note content stays outside this repo.
- `termux/`: Android/Termux dotfiles and Termux:Widget shortcuts.
- `assets/`: static assets, patches, scripts, firmware, udev rules, media.
- `tests/`: test runner and helpers.
- `docs/`: durable operational notes; add focused docs here instead of bloating startup context.
- `for-my-eyes-only/`: private package/submodule; do not touch without explicit request.

## Ansible

- Main playbook: `playbooks/tools.yml`; roles use numeric task filenames and tags such as `10-40`.
- OS variants use `.archlinux.yml`, `.debian.yml`, `.android.yml`, `.macosx.yml`; `with_first_found` means missing variants can be valid.
- Templates live under `playbooks/roles/<role>/templates/`; patches usually under role `files/` or `assets/patches/`.
- Use `ansible_facts.*` for gathered facts, not auto-injected top-level fact vars.
- Include `{{ ansible_managed }}` in templates when the format supports comments.
- Central idempotence markers live in `playbooks/roles/dotfiles-markers/` and `~/.local/state/dotfiles/ansible-markers/`; do not create marker files in checkouts/install dirs.
- Reuse existing setup owners before adding bootstrap, service, package-manager, or shared-tooling tasks.
- Do not run full system upgrades from Ansible.

## Stow

- Stow packages are applied from the repo root through `~/bin/dotfiles-stow`.
- The `playbooks` package is intentionally **not** stowed: its Ansible config is read in-repo from `~/dotfiles/playbooks` (cwd or `ANSIBLE_CONFIG`), so the `10-30` apply must not see it in `dotfiles_public_stow_packages`.
- Use `dot-*` names for hidden targets and `.stow-local-ignore` for files that must not link into `$HOME`.
- New files under stowed packages are inactive until stowed; edited existing symlinked files update in place.
- `dotfiles-stow` refreshes the generated Firejail include that exposes active Stow targets to sandboxed AI agents without opening all of `$HOME`.
- Use `dotfiles-stow --recreate [--dir=...] <package>...` to migrate links between Stow directories; plain `--restow` does not migrate.
- Termux packages are applied only by `android` tasks to `phone2`; widgets must be real executable files, not symlinks.

## Frequent Ownership

- Keyboard/mouse-free workflow: `keyd-default.conf`, `peripherals/bin/keyd-observer`, `warpd-*`, `mode-osd`, mouseless configs.
- DWM/compositor: `playbooks/roles/10-system-tools/tasks/100-setup-compositor.archlinux.yml` and DWM patches under role `files/`.
- Display/tablet: Xorg defaults under role `files/wacom/`; runtime display/tablet logic in `peripherals/bin/wacom-config.sh`, `utilities/bin/setup-displays.sh`, `display-health-check`, `x11-monitor-geometry`.
- Neovim jobs/agents: job modules under `nvim/.../plugins/jobs/`; shared agent task/session helpers in `agent_sessions.lua`, `agent_tasks.lua`, `utilities/bin/agent-tasks`, `utilities/bin/agent-session-store`.
- Promnesia agent-conversation indexing: source at `PKM/dot-config/promnesia/agent_conversations.py`, registered in `PKM/dot-config/promnesia/config.py`; editor routing for conversation links lives in `nvim/bin/nvr_open_nvim.sh` and the `agent_conversation` handler in `nvim/bin/open_in_nvim`; the firejail exposure for the transcript dirs is in `playbooks/roles/20-dev-tools/templates/fj-py-promnesia.profile`.
- Kitty/tmux: socket/window naming in `term/bin/kitty-window-utils.sh`; tmux copy marks in `term/bin/tmux-copy-mark` and `term/dot-config/tmux/copy-mode-marks.conf`, with the per-session persisted mark files at `$XDG_STATE_HOME/dotfiles/tmux-copy-mark/state-<session-name>` and per-session snippet/label metadata at `state-<session-name>.labels`.
- DWM scratchpad terminal: dwm-bound plain-shell quick-access panel in `term/bin/kitty-scratchpad-quick-access`, floated via the `kitty-scratchpad` rule in `custom.patch`; workflow notes in `docs/dwm-scratchpad.md`.
- Notifications: clickable actions go through `utilities/bin/notification-action` with allowlisted JSON payloads; notification sounds are attached per-category via the dunst rule `script` option, e.g. `utilities/bin/notification-sound`.
- System health: `dotfiles-health`, `system-spike-watch`, `dotfiles-spikes`, `dotfiles-health-notify`, `browser-task-snapshotd`; keep watchers cheap and incremental.
- Storage labels/automount: `arch_filesystem_autolabels`/`arch_filesystem_automounts` in `main.vars.yml`, applied by `200-setup-file-manager-tools.archlinux.yml`; MTP devices use `arch_mtp_automounts` (jmtpfs) in the same task file; operational notes in `docs/storage-automount.md`.
- KDE runtime: tracked shortcuts in `utilities/dot-config/kglobalshortcutsrc`; live KDE state is applied by the Arch dotfiles task, not manual edits.
- Audio/MIDI/pedalboard/REAPER/Wine: detailed operational notes are intentionally in focused docs/assets; pedalboard profile ownership is in `docs/pedalboard-midi.md`. Keep Wine prefix setup in shared roles and use `wwine` contracts instead of ad hoc Wine wrappers. Windows VST bridges are installed as yabridge/LinVst-X (tag `10-130`) and Carla (`10-135`); Carla's bridge binaries are cross-compiled from the matching Carla tag by `135-setup-carla-tools.archlinux.yml`, and `templates/carla2.conf` pins its Wine bridge to the system Wine profile on the Reaper prefix without writing into the native VST scan paths yabridge/LinVst-X own.
- Native REAPER SWS extension is built from source with repo-owned patches (`assets/patches/sws/`, `tasks/wine-tools/sws-patched-linux.task.yml`, `arch_sws_patched_setup`); the distro `sws` package is removed and the patched build installs into `~/.config/REAPER/UserPlugins`. Patch workflow and version/patch-set bump semantics in `docs/sws-patched-build.md`.
- Native DAW launchers share one low-latency profile: `launch-reaper-linux`, `launch-ardour`, `launch-bitwig` and `launch-studio-one` under `10-system-tools/templates/` (copied to `~/.local/bin/`) all export the same `audio-latency` PipeWire quantum/rate env (PIPEWIRE_LATENCY/QUANTUM/RATE from `~/.config/dotfiles/audio-latency.defaults.env`, default 256 @ 48 kHz) and raise governor/platform/SMT for the session; the matching `.desktop` overrides (`ardour-low-latency.desktop`, `com.bitwig.BitwigStudio.desktop`, `com.presonus.studioapp7.desktop`) point at those launchers. Ardour/Bitwig run natively on X11; Studio One is wrapped in nested weston (see the Studio One bullet).
- Studio One 7 (PreSonus native Linux): install recipe pinned in `10-system-tools/files/studio-one-7/PKGBUILD` (AUR mirror) and built by `210-setup-audio-tools.archlinux.yml` from the manual `.deb` at `arch_studio_one_deb_path` (`~/data/Downloads/music-production/external-libraries/studio-one-7/`, outside the repo); `files/sdbus-cpp1/` mirrors the ABI-compat AUR package that provides `libsdbus-c++.so.1` (current Arch `sdbus-cpp` is 2.x/.so.2) and is built first when missing. The build only runs as a Wayland client, so on the X11 KDE session `templates/launch-studio-one` hosts it inside nested weston (X11 backend) and the user `com.presonus.studioapp7.desktop` override replaces the deb's malformed Exec. Version bumps update `arch_studio_one_version` in `main.vars.yml` plus the PKGBUILD `sha256sums`. Personal prefs (`~/.config/PreSonus`) and user projects (`~/Studio One`) are deliberately unmanaged.
- Repo-built LADSPA plugins (currently `files/ladspa-agc-ceiling.c`, compiled to `/usr/lib/ladspa/` by `210-setup-audio-tools.archlinux.yml`): PipeWire keeps the previous `.so` mapped for the lifetime of the service, so the build task must notify `handler_restart_pipewire`/`handler_restart_pipewire_pulse` or a rebuilt plugin sits on disk while the running graph keeps the old code. A plugin's port tables and the `control` block of its filter-chain fragment in `audio/dot-config/pipewire/pipewire.conf.d/` are one contract and have to be deployed together; PipeWire discards a control whose name it cannot find as an input port without logging anything, so port tables use designated initializers keyed on the port enum and `tests/audio/audio_normalization.sh` asserts the declared directions, the measured output ceiling, and that the leveler is not frozen.

## Hot-Path Rules

- Avoid Python for always-on, high-frequency, latency-sensitive, or freeze-path scripts; prefer Go/C/Rust or bounded shell wrappers that exec cached binaries.
- Prefer event-driven watchers over polling. If polling is unavoidable, keep it bounded, low-frequency, and documented.
- For high-frequency device events, avoid per-event subprocesses, RPC calls, active-system writes, and persistent mirror files; keep mapping in a resident process and quantize downstream UI feedback.
- Runtime Neovim paths must not block the main loop with recursive scans, large reads, synchronous JSON parsing, waits, or polling; use async APIs/background jobs.
- For cross-tool runtime identity, reuse central resolvers such as `kitty-window-utils.sh` and `open_in_nvim` rather than reimplementing socket/server naming.
- Prefer event-driven desktop state monitors for desktop action feedback; avoid polling loops in `desktop-state-monitor` unless the bounded fallback is documented and tested.
