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
- The `playbooks` package is intentionally **not** stowed: its Ansible config is read in-repo from `~/dotfiles/playbooks` (cwd or `ANSIBLE_CONFIG`), so the `10-30` apply and the pre-commit Stow guard must not see it in `dotfiles_public_stow_packages`.
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
- Kitty/tmux: socket/window naming in `term/bin/kitty-window-utils.sh`; tmux copy marks in `term/bin/tmux-copy-mark` and `term/dot-config/tmux/copy-mode-marks.conf`, with the persisted mark pool at `$XDG_STATE_HOME/dotfiles/tmux-copy-mark/state`.
- DWM scratchpad terminal: dwm-bound plain-shell quick-access panel in `term/bin/kitty-scratchpad-quick-access`, floated via the `kitty-scratchpad` rule in `custom.patch`; workflow notes in `docs/dwm-scratchpad.md`.
- Notifications: clickable actions go through `utilities/bin/notification-action` with allowlisted JSON payloads.
- System health: `dotfiles-health`, `system-spike-watch`, `dotfiles-spikes`, `dotfiles-health-notify`, `browser-task-snapshotd`; keep watchers cheap and incremental.
- Storage labels/automount: `arch_filesystem_autolabels`/`arch_filesystem_automounts` in `main.vars.yml`, applied by `200-setup-file-manager-tools.archlinux.yml`; operational notes in `docs/storage-automount.md`.
- KDE runtime: tracked shortcuts in `utilities/dot-config/kglobalshortcutsrc`; live KDE state is applied by the Arch dotfiles task, not manual edits.
- Audio/MIDI/pedalboard/REAPER/Wine: detailed operational notes are intentionally in focused docs/assets; pedalboard profile ownership is in `docs/pedalboard-midi.md`. Keep Wine prefix setup in shared roles and use `wwine` contracts instead of ad hoc Wine wrappers.

## Hot-Path Rules

- Avoid Python for always-on, high-frequency, latency-sensitive, or freeze-path scripts; prefer Go/C/Rust or bounded shell wrappers that exec cached binaries.
- Prefer event-driven watchers over polling. If polling is unavoidable, keep it bounded, low-frequency, and documented.
- For high-frequency device events, avoid per-event subprocesses, RPC calls, active-system writes, and persistent mirror files; keep mapping in a resident process and quantize downstream UI feedback.
- Runtime Neovim paths must not block the main loop with recursive scans, large reads, synchronous JSON parsing, waits, or polling; use async APIs/background jobs.
- For cross-tool runtime identity, reuse central resolvers such as `kitty-window-utils.sh` and `open_in_nvim` rather than reimplementing socket/server naming.
- Prefer event-driven desktop state monitors for desktop action feedback; avoid polling loops in `desktop-state-monitor` unless the bounded fallback is documented and tested.
