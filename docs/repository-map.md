# Repository Map

This map describes where changes usually belong. It is intentionally practical: start here when deciding which file owns a behavior.

## Top-Level Packages

- `playbooks/`: Ansible entrypoints, roles, templates, filters, and local modules.
- `peripherals/`: keyboard, mouse, tablet, keyd, mouseless, warpd, and related user services/scripts.
- `nvim/`: Neovim config and wrappers.
- `term/`: terminal wrappers, Kitty-related tooling, and tmux configuration.
- `systemd/`: user-level systemd units that are not tied to a narrower package.
- `audio/`: audio production and routing configuration/scripts.
- `utilities/`: general user scripts and utility configs.
- `dunst/`: notification daemon configuration.
- `lazygit/`: lazygit configuration. See [lazygit.md](./lazygit.md) for pager and diff setup.
- `home/`: generic home-directory dotfiles.
- `PKM/`: personal knowledge management tooling.
- `termux/`: Termux-only dotfiles, including add-on integrations such as Termux:Widget shortcuts.
- `tests/`: persistent dotfiles test runner, unit-specific test files, and test helpers. See [dotfiles-testing.md](./dotfiles-testing.md).
- `assets/`: static assets, patches, scripts, services, udev rules, and media.
- `docs/`: human-readable operational notes and project context.
- `for-my-eyes-only/`: optional private package and submodule. Do not touch unless explicitly requested. Package-specific private assistant context should live at `for-my-eyes-only/docs/agent-context.md`; the public Ansible role links shared agent entrypoints into this package when it exists.

## Terminal Tooling

Kitty remote-control socket naming is owned by `term/bin/kitty-window-utils.sh`. Scripts that need CWD-derived Kitty socket paths, `listen_on` values, or matching Neovim server names should source that file instead of reimplementing the naming rule. `term/bin/kitty` only binds those cwd sockets for explicit directory launches (`-d`, `--directory`, or `--working-directory`), so plain dwm-style terminal launches do not collide on an inherited cwd. Long CWD keys are shortened with a stable hash so socket paths stay within UNIX socket path limits.

## Ansible Structure

The main playbook is `playbooks/tools.yml`. It gathers facts, detects some host state, then imports roles in numeric order. Roles use numeric task filenames to make execution order visible.

```text
playbooks/roles/10-system-tools/
playbooks/roles/20-dev-tools/
playbooks/roles/30-lang-tools/
playbooks/roles/40-PKM/
playbooks/roles/50-cloud-tools/
```

Common patterns:

- OS-specific task files use suffixes such as `.archlinux.yml`, `.debian.yml`, `.otherlinux.yml`, and `.macosx.yml`.
- Role task files are included through `with_first_found`, so missing OS files can be valid.
- Role tags follow the role/task number, such as `10-40` or `20-90`.
- Embedded hardware and serial development is owned by `playbooks/roles/20-dev-tools/tasks/200-setup-embedded-tools.archlinux.yml`; tag `20-200` installs Arduino CLI tooling, AVR board support, serial-port access through the Arch `uucp` group, Arduino Micro udev rules from `assets/udev-rules/`, and compiles/uploads the keyboard MIDI LED matrix firmware when the Arduino Micro is connected and the firmware hash changed.
- Templates live under `playbooks/roles/<role>/templates/`.
- Patches used by playbooks usually live under `playbooks/roles/<role>/files/` or `assets/patches/`.

## Stow Model

Dotfile packages are stowed from the repository root. Public packages are applied in `10-system-tools/tasks/30-setup-dotfiles.*.yml`.

Important conventions:

- Use `dot-*` names for files/directories that should become hidden dotfiles.
- Keep each top-level package focused on one area of the system.
- `.stow-local-ignore` files prevent irrelevant files from being linked into `$HOME`.
- Stow is invoked through the generated `~/bin/dotfiles-stow` wrapper, which applies `dotfiles_stow_options` and `dotfiles_stow_ignore_patterns` from the `10-system-tools` defaults, plus the configured agent context filenames. The wrapper always changes to the generated user's `~/dotfiles` before invoking Stow, so it can be run from any directory. Use `dotfiles-stow --recreate [--dir=/path/to/alternate-dotfiles] <package>...` when packages should first be unstowed from their current Stow directory and then stowed from the requested tree; when `--dir` is omitted, the requested tree is the managed `~/dotfiles`. GNU Stow's own `--restow` only restows from the currently selected Stow directory and does not migrate links between different `--dir` trees.
- Private packages are listed separately in `dotfiles_private_stow_packages`. `for-my-eyes-only/docs/agent-context.md` is also ignored by the wrapper so private AI notes can remain in the package without being linked into `$HOME`.
- Termux-specific packages are listed separately in `dotfiles_otherlinux_stow_packages` and applied only by the `otherlinux` dotfiles task so Android does not receive desktop package symlinks. The `otherlinux` task syncs those package directories from the Ansible controller before installing active files, so local package additions do not depend on the phone's Git clone already containing the latest commit. Termux:Widget scripts must be copied as real files under `~/.shortcuts` or `~/.termux`, because the widget hides symlinks whose canonical path points elsewhere. Android browsers do not use Termux's private hosts file, and unprivileged Termux processes cannot bind low ports such as `80`, so browser shortcuts for local web UIs should open the explicit loopback URL via `termux-open-url`.
- Termux widgets that need a helper from a non-Termux package should have that specific helper copied by the `otherlinux` dotfiles task rather than adding the whole package to `dotfiles_otherlinux_stow_packages`; for example, `rem-list` uses the shared `PKM/bin/remind-agenda` helper through a copied `~/dotfiles/PKM/bin/remind-agenda` file.
- Termux `pkg install` calls are not cheap enough to run unconditionally in every playbook pass. In `.otherlinux.yml` tasks, check package status first with `dpkg-query -W -f='${Status}'` and call `pkg install -y` only for missing packages.
- Termux active-system application must target the phone inventory host. When suggesting or running Ansible for `termux/` files, `otherlinux` tasks, or Termux:Widget shortcuts, use `ansible-playbook ... -l phone2 --tags ...`; `-l localhost` applies the laptop configuration and will not update `~/.shortcuts/tasks/` on the phone.
- Termux services with local web UIs should get a matching Termux:Widget task named `<service>-gui` under `termux/dot-shortcuts/tasks/`. Keep those scripts as small POSIX `sh` launchers that call `termux-open-url` with the explicit `http://127.0.0.1:<port>/` URL. The `otherlinux` dotfiles task installs every script in that directory as a real executable under `~/.shortcuts/tasks/`.
- Termux:Widget tasks that generate files for Android browsers should write browser-opened files to shared Android storage such as `~/storage/downloads` or `/storage/emulated/0/Download`, not to Termux-private paths such as `/data/data/com.termux/files/usr/tmp` or `~/.local/state`. Browser `content://com.termux.files/...` handoff can report `ERR_FILE_NOT_FOUND` for private Termux paths even when the file exists.
- The most robust pattern for opening generated Termux:Widget HTML in Chrome is to write the file to `/storage/emulated/0/Download/`, serve that directory from Termux on an explicit loopback URL such as `http://127.0.0.1:<port>/reminders.html` with a short fixed lifetime such as 60 seconds, and keep the Files by Google provider URI only as a fallback; direct `content://...` handoff can regress back to `ERR_FILE_NOT_FOUND` even when the shared-storage file exists.
- Termux shortcuts for laptop-hosted web UIs should not hard-code a DHCP address. The `send-ifconfig.service` user unit on the laptop runs `utilities/bin/send-ifconfig`, which publishes `~/laptop-lan.env` on `phone2`; `/etc/NetworkManager/dispatcher.d/90-send-ifconfig` starts that service after usable network changes, and shortcuts such as `overseerr-gui` should read the published file before calling `termux-open-url`.
- Existing symlinked files update in place when edited in the repository, but newly added files under a stowed package are not active until that package is stowed again. For example, after adding a file under `nvim/`, run `~/bin/dotfiles-stow nvim` or include the dotfile setup task in the next Ansible run.

## Neovim

Task-runner and job-management modules belong under `nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/`. Runtime plugin entrypoints under `nvim/dot-config/nvim/plugin/` should only load those modules. Agent CLI integrations for Overseer are provider-based: shared picker/task/session behavior belongs in `agent_sessions.lua`, while provider-specific discovery belongs in `utilities/bin/agent-session-store`. That command is a thin compile/cache wrapper around the Go source in `utilities/dot-local/share/dotfiles/agent-session-store/`; preserve its JSON CLI contract and update the `10-30` dotfiles compile-cache task when the cached build behavior changes. Repository-owned Overseer task output should use the shared `utils.schedule_open_overseer_task_output()` helper so outputs replace/reuse a regular window instead of using Overseer float/tab output directions by default. Neovim terminal windows should stay visually plain through the global terminal-window autocmd: no line-number, sign, or fold columns while a terminal buffer is displayed, with previous regular window options restored when a regular buffer is shown in that same window or in a new window cloned from the terminal window. Because repository helpers intentionally make Overseer output buffers listed, they must also attach dispose cleanup that replaces visible output windows, deletes the output buffer when possible, and at minimum marks it unlisted. Visual-mode agent-session keymaps should capture the selected snippet before leaving Visual mode, then leave Visual before opening a picker or starting an Overseer task so terminal creation and pasted prompts are not blocked by Visual mode. Overseer output helpers should open task buffers with normal buffer commands such as `:buffer` instead of swapping windows through scratch buffers or maintaining synthetic alternate-buffer state; this keeps `<C-6>` governed by Neovim's own buffer history. Do not reattach Overseer task terminal keymaps from a buffer-local `BufEnter`; attach once when the terminal buffer exists, because reattaching on terminal entry can interfere with native alternate-buffer updates. Picker terminals may use `startinsert()`, but paths that return from a picker to a persistent terminal must clear Terminal-mode with `stopinsert` before focusing the persistent output. Picker terminal buffers are transient and should be wiped after the picker closes so they do not remain hidden in buffer history or pollute native alternate-buffer behavior. Picker sinks that open another picker should run after the closing picker has finished terminal cleanup, for example with `vim.schedule`, so `stopinsert` from the old picker cannot cancel `startinsert` on the next picker. Picker flows that start asynchronous Overseer tasks must capture the launching window and pass that `winid` to `utils.schedule_open_overseer_task_output()` because the task callback may run after focus has moved. Modules required from `nvim/dot-config/nvim/after/ftplugin/` should not require optional plugin dependencies at top level. Check plugin availability before enabling plugin-specific behavior so opening a buffer still works after the plugin directories have been removed and before Ansible restores them. Global keymaps and commands should also guard optional plugin calls so basic editor actions such as quitting remain available without the plugin pack.

Runtime code on interactive Neovim paths must not block the main event loop with recursive scans, large file reads, JSON parsing over many files, shell waits, or polling loops. `vim.defer_fn()` delays synchronous work but still runs it on the main loop. Prefer `vim.uv` async APIs and the `promise-async` plugin (`require("promise")` / `require("async")`), using background jobs for expensive parsing or discovery. See [neovim-runtime-performance.md](./neovim-runtime-performance.md).

## Shared Runtime Cache

Use Valkey for small cross-process runtime caches that need to be shared by Neovim, Kitty helpers, shell scripts, or Python scripts. `utilities/bin/cachectl` wraps `valkey-cli` with the repository key namespace `dotfiles:cache:v1:<namespace>:<key>` and requires TTLs for stored values. Values should be cheap to rebuild and should not be committed.

## Update Diff Capture

Package updates that should leave inspectable before/after diffs use the explicit `playbooks/roles/update-diff-capture/` role. See [update-diff-capture.md](./update-diff-capture.md). The role installs `update-diff-capture` and `update-diffs`, stores captures under `~/.local/state/dotfiles/update-diffs/`, and keeps capture opt-in at the task callsite instead of intercepting package managers through callbacks or action plugins.

Version pins that should be proposed automatically are owned by the root `renovate.json`. See [dependency-update-pins.md](./dependency-update-pins.md). Keep Renovate metadata in that config rather than inline comments in Ansible YAML, and keep AUR package review in `aur-review`.

GitHub rate-limit mitigation is centralized in `utilities/bin/dotfiles-github-token`, `utilities/bin/dotfiles-github-askpass`, and `utilities/bin/dotfiles-github-git`. These helpers read a non-empty token from environment or KWallet only at runtime, fall back to anonymous requests when no token exists, and are used by Renovate lookups, `aur-review` upstream Git fetches, `update-diff-capture` Git archives, and direct Ansible GitHub checkouts that are not bootstrap clones of `~/dotfiles`.

## Performance-Sensitive Scripts

Avoid Python for always-on, high-frequency, latency-sensitive, or interactive-path scripts. Use a compiled implementation such as Go, C, or Rust when the tool polls, samples `/proc`, watches input/display/audio state, runs inside a systemd service for the whole session, or may execute during freezes. A thin shell wrapper that compiles a cached binary is acceptable when it immediately `exec`s the compiled program for normal runtime.

Python remains acceptable for bounded generators, report writers, one-shot maintenance commands, tests, and tools whose runtime cost is dominated by external APIs or human-triggered work. When moving a hot script to a compiled implementation, keep the source in the owning stow package, keep generated binaries out of Git, and add Ansible/test coverage for cache compilation.

## Notification Actions

Clickable notification behavior is routed through `utilities/bin/notification-action`. Producers should send a versioned JSON payload with `schema: dotfiles.notification-action.v1`, `action`, and action-specific metadata such as `cwd` and `foam-section-id`; the helper encodes that payload into a Dunst notification action name and dispatches the selected action after the click. Keep action implementations allowlisted in that helper and delegate editor work through `nvim/bin/open_in_nvim` so CWD-derived Kitty and Neovim socket naming remains centralized in `term/bin/kitty-window-utils.sh`.

## System Health Notes

`utilities/bin/dotfiles-health` generates a compact workstation health report under the private Foam notes tree at `ops/system-health/`. The user timer lives in `utilities/dot-config/systemd/user/dotfiles-health.timer` and is enabled by the Arch dotfiles task after Stow has linked the utility and unit files.

`utilities/bin/system-spike-watch` is the always-on lightweight CPU spike sampler. It is a shell wrapper that compiles and `exec`s the Go source under `utilities/dot-local/share/dotfiles/system-spike-watch/`, with the runtime binary cached under `~/.cache/dotfiles/system-spike-watch/`. It stores compact JSONL events under `~/.local/state/dotfiles/system-spikes/events/`; `utilities/bin/dotfiles-spikes` turns those events into Foam reports under `ops/system-health/spikes/`. `utilities/bin/system-spike-notify` is the separate notification layer: it watches the event directory, refreshes `dotfiles-spikes`, and only then sends clickable `notification-action` notifications for new Xorg events. Their user units live in `utilities/dot-config/systemd/user/system-spike-watch.service`, `system-spike-notify.service`, `dotfiles-spikes.service`, and `dotfiles-spikes.timer`, and are enabled by the same Arch dotfiles task. `utilities/bin/browser-task-snapshotd` is a companion local HTTP receiver for browser Task Manager CPU snapshots from the `Dotfiles Browser Task Sampler` extension; it writes latest snapshots under `~/.local/state/dotfiles/browser-task-sampler/` and is managed by `browser-task-snapshotd.service`. Keep the watcher cheap: no subprocess loops in normal sampling, no journal crawling, and no Markdown writes from the service. Burst-only enrichment may query the active X11 window through `xdotool`, predictable Kitty sockets, local Chromium-family DevTools ports including short CDP tab activity probes, fresh browser task snapshots, `docker inspect`, `pw-top`, and `pw-dump` for ambiguous Xorg, `kitty-*`, `browser-brave-*`, `browser-chromium-*`, `docker-*.scope`, and audio-path events; this must stay bounded and outside the normal one-second sampling loop.

Keep this workflow Markdown-first: write stable summaries, Foam links, Remind TODOs, and executable `journalctl`/`systemctl` snippets. Do not dump raw journal output into notes except for a few short evidence lines when a human-written issue note needs them.

The health report should not treat journald as the only source of truth. Keep the default scans cheap and bounded, and summarize only high-signal evidence from non-journal sources such as system failed units, `coredumpctl`, `/var/log/Xorg.0.log`, `/var/log/pacman.log`, and targeted kernel patterns. Generated source pages should live under `ops/system-health/sources/`, use unique Foam file stems such as `system-health-kernel`, and include executable Markdown fences for deeper inspection instead of storing large raw logs. Coverage should be explicit: `system-health-coverage` documents watched domains and partial blind spots, and `system-health-unclassified` summarizes recent journal warning families that did not match a known classifier. Treat those unclassified families as a promotion queue: actionable repeated patterns become focused detectors plus `rules.md` entries, while accepted noise is documented as ignored noise instead of disappearing silently. Generated snippets must be bounded by default. Avoid unbounded `journalctl --since ... --no-pager` commands in notes; prefer `journalctl -n` with `SYSTEMD_PAGER='less -R +G'` and `--pager-end` so terminal runs open in a searchable pager while non-interactive runs still finish quickly. For piped file scans, limit the input with `tail` or the output with `sed -n` so readonly notes never force the user to wait on an accidental full-log dump.

In Neovim buffers, executable shell fences can be run with `<leader>mr` wherever the current buffer lines contain a `sh`/`bash`/`shell` fence, including file-backed Markdown, scratch, `nofile`, and terminal buffers in Terminal-Normal mode. The keymap launches the current fence through Overseer and opens the task output in a regular window, so generated notes can keep commands as snippets instead of storing volatile log output. Keep this path covered by `tests/nvim/overseer_shell_fences.sh`; shell-fence tasks should include Overseer's `on_complete_dispose` with `require_view` for success and failure statuses so completed fence runs do not keep polluting task history after their output has been shown, and their cwd resolver must fall back to `getcwd()` when the source buffer has no local file path.

## Dev Tool Sandboxing

Python and Node package-manager installs and routine tool execution should use the Firejail wrappers owned by `playbooks/roles/20-dev-tools/`. The same supply-chain posture applies broadly to new tools, apps, AUR packages, upstream binary downloads, model downloaders, installer scripts, browser automation, and language package registries. Use package-manager-owned installs when they keep ownership and upgrades reproducible, but sandbox new install or runtime paths unless there is a documented reason not to. See [firejail-dev-tools.md](./firejail-dev-tools.md) for wrapper contracts, Ansible adapter examples, network modes, and profile guidance.

## Private Notes

The personal notes tree at `~/data/notes/foam` is private and must not be inspected unless a task explicitly grants access. Its agent context entrypoint is `AGENTS.md` inside that private tree. The `40-PKM` role's `40-50` tag creates tool-specific compatibility symlinks such as `CLAUDE.md` and `GEMINI.md` only when the private notes directory and its `AGENTS.md` file already exist.

Remind helper files for note TODO reminders belong under `PKM/dot-config/remind/` and are stowed into `~/.config/remind/`. Runtime callers should pass `~/.config/remind/` as the Remind input directory, so Remind loads sorted `*.rem` files such as `00-helpers.rem` before generated `reminders.rem`. Keep `~/.config/remind/reminders.rem` generated from Neovim; durable helper functions belong in the dotfiles package instead.

## Voice Workflows

Text-to-speech wrappers for narrating terminal commands, TUIs, and AI CLIs live in `utilities/bin/` and are documented in [voice-agent-workflows.md](./voice-agent-workflows.md). Speech-to-text dictation also lives in `utilities/bin/`, with keyboard signals bridged through `peripherals/bin/keyd-observer` and `playbooks/roles/10-system-tools/templates/keyd-default.conf`.

The voice fallback layer should stay local and reproducible. Keep package ownership explicit for dependencies such as `speech-dispatcher`, `espeak-ng`, and `python-vosk`. Python-based voice engines should run through the repository Firejail wrappers by default; document any exception in `voice-agent-workflows.md`.

## REAPER

REAPER scripts that should be managed by Ansible live in `assets/scripts/reaper/`. Native Linux REAPER startup hooks are installed from `assets/scripts/reaper/__startup.lua` by the `10-120` wine-tools task into `~/.config/REAPER/Scripts/__startup.lua`; keep per-feature startup logic in separate files under `Scripts/custom/` and load them from that entrypoint. Helgobox/ReaLearn native Linux assets are also installed by the `10-120` wine-tools task: the VST goes to `~/.vst/` and the REAPER extension goes to `~/.config/REAPER/UserPlugins/`, with the pinned release metadata in `arch_helgobox_setup`; the task patches the VST's `libxdo.so.3` dependency to Arch's current `libxdo.so.4` with `patchelf` so REAPER can scan it. WineASIO for Windows REAPER is built by the same `10-120` wine-tools task from `wine-tools/wineasio.task.yml`, installed into both the managed portable Wine tree and system Wine tree, and registered into the Reaper Wine prefix. Wine commands launched through `~/bin/wwine` use Wine's virtual desktop by default. Keep the default virtual desktop registry name as `Default`: installer wait loops poll `wmctrl -lx` for `explorer.exe`, and the DWM Wine rule relies on Wine's virtual desktop window identity staying stable. The default virtual desktop size is derived at runtime from the current X11 monitor through `utilities/bin/x11-monitor-geometry`; use `wwine --desktop=<WxH>` only for intentional fixed-size overrides. `wwine` is also installed as `~/bin/wwine-wine-loader`, a `WINELOADER`-compatible entrypoint for yabridge and similar tools that need to launch Wine through the managed environment without passing wrapper arguments. When `wwine --use-sandbox` is invoked from an existing Firejail sandbox, it must validate the inherited sandbox with `fj-profile-checker` before reusing it instead of relying on marker environment variables. The Reaper Wine prefix uses a stable Firejail sandbox name so parallel yabridge host launches reuse the same fixed-IP sandbox through `firejail --join-or-start`; `wwine` serializes named sandbox startup with a runtime lock and releases the lock as soon as Firejail registers the sandbox name, so parallel yabridge probes do not race to create duplicate fixed-IP sandboxes. Native Linux REAPER launched through `reaper-linux-firejail.desktop` must use the same `wwine-reaper` Firejail sandbox name as `wwine --prefix reaper --use-sandbox`, otherwise external Wine launchers such as external Wine audio server cannot join the already-running fixed-IP sandbox.
Controller-specific REAPER hardware protocol references and mapping source data belong under `assets/reaper/<device>/`; runtime helpers that should be callable from the shell belong in the owning Stow package, such as `audio/dot-local/bin/`.
Launcher-scoped PipeWire latency for REAPER and AudioGridder lives in `pipewire_latency_vars` under `playbooks/roles/10-system-tools/defaults/main/music-production.vars.yml`; keep `arch_wineasio_setup.reaper_block_size` aligned with that quantum when changing the test buffer for Windows REAPER. Desktop Pulse clients are kept at the normal 1024-sample floor by `audio/dot-config/pipewire/pipewire-pulse.conf.d/10-default-quantum.conf`, so browsers and media players should not pull the graph below the workstation default while JACK production launchers can still request lower latency.

## Keyboard And Mouse-Free Workflow

The keyboard/mouse stack is split across keyd, a small observer script, warpd, and mouseless.

```text
keyd-default.conf
  emits layers and macros

keyd-observer
  listens for keyd signal layers and starts user-session actions

warpd-last-location
  wraps warpd hint/toggle behavior and stores cursor points in tmpfs

warpd-marker
  keeps a small input-transparent X11 marker on the point tab+g would jump to

warpd-trail
  draws a visual overlay after a warpd jump without moving the real cursor

mode-osd
  keeps persistent mouse, readline, and MIDI mode indicators in an input-transparent X11 overlay

keyboard-midi-controller
  observes keyd MIDI layers and emits BeatStep-style MIDI through ALSA and JACK/PipeWire virtual ports

mouseless config
  owns keyboard-driven mouse movement and mouse buttons
```

`warpd-marker`, `warpd-trail`, and `mode-osd` compile their embedded X11 helpers into stable cache paths under `~/.cache`. Do not bump helper filenames for code changes; the wrappers compare the generated C source with the cached source and rebuild when needed. The keyboard-tools Ansible task precompiles the stable helpers. The compositor template excludes `WM_CLASS=warpd` windows from picom fading so `tab+f` hint overlays appear and disappear without fade latency. Keep `warpd-last-location run-hint` latency-sensitive: launch `warpd` before auxiliary cursor-state work such as `xdotool getmouselocation`, then reconcile `previous`, `last`, and trail state after the hint selection returns.

When fixing keyboard conflicts, first identify who consumes the key:

- keyd mapping
- mouseless mouse layer
- warpd mode
- dwm binding
- application-level shortcut

Then prefer the smallest translation at the layer that already owns similar conflicts. If a KDE global shortcut overlaps a keyd modifier layer, prefer moving it to a non-`Meta` chord such as `Ctrl+Alt+V` before adding passthroughs. Plain `Meta+V` and `Meta+C` are owned by keyd's Gromit bindings. In the DWM session, `Ctrl+Alt+V` is owned by keyd and handled by `keyd-observer`, which calls Klipper's `org.kde.klipper.klipper.showKlipperPopupMenu` D-Bus method directly. Do not also bind that chord in KDE global shortcuts.
MIDI controller mode is owned by keyd layers end to end: `Tab+m` toggles the persistent `midi` layer directly, `Esc` exits that layer, and the Go `keyboard-midi-controller` daemon listens to `keyd listen` for `+midi`, `+midi_enc_*`, `+midi_pad_*`, direct selector layers, and utility layers. Do not route MIDI mode through `keyd-application-mapper`, direct `command(...)` keyd actions, evdev reads, or `EVIOCGRAB`; keyd remains the only physical keyboard consumer, which avoids raw-key leakage in REAPER without fighting the existing keyd grab. The daemon keeps MIDI state, repeats held encoder layers, exposes an ALSA virtual output port plus a JACK/PipeWire MIDI output port, and owns the persistent MIDI mode OSD through `show_keyboard_midi_osd`/`hide_keyboard_midi_osd` while active. REAPER should see the JACK/PipeWire port as a MIDI input named from the `Keyboard MIDI Controller` client and `BeatStep Out` port; keep the ALSA port marked as `SND_SEQ_PORT_TYPE_HARDWARE | SND_SEQ_PORT_TYPE_PORT` and the JACK port marked `JackPortIsPhysical | JackPortIsTerminal` because REAPER's MIDI device list filters out plain application ports. LED matrix feedback must follow the controller flow: HHKB/keyd sends control events to the daemon, the daemon sends control MIDI to REAPER/ReaLearn, REAPER/ReaLearn sends feedback to the daemon's `Keyboard MIDI Controller Feedback:Feedback In` port, and only the daemon writes final LED state through `Keyboard MIDI Controller LED:LED Out` to the Arduino matrix. The daemon owns the runtime ALSA subscription from `Keyboard MIDI Controller LED:LED Out` to `Arduino Micro MIDI 1` and retries by port name so Arduino USB reconnects and dynamic ALSA client IDs do not require manual `aconnect`. Do not make REAPER the normal direct writer to the Arduino, because that bypasses daemon-owned mode/bank/transport state. The Arduino firmware source for the simple Note 36-99 LED addressing protocol lives under `assets/firmware/keyboard-midi-led-matrix/`. The keyd template now needs the local `increase-max-layers-for-midi.patch` so keyd supports the expanded BeatStep-style MIDI layer set; keep `keyd check` in the keyboard-tools task so template changes are validated against the patched binary. Normal exit releases held notes only, while the explicit `panic` command sends all-notes-off and reset-controller CCs. MIDI mode must not send mouse-mode escape chords as part of enter/toggle handling. `Tab+space` while MIDI mode is active is handled in keyd's `midi+tab_as_modifier` composite layer with `togglem(midi, macro(leftcontrol+rightcontrol))`, so keyd exits the persistent MIDI layer and mouseless enters mouse mode without routing the transition through the daemon. Mouse mode, readline mode, and MIDI mode OSD state is shown by `peripherals/bin/mode-osd`, an override-redirect X11 overlay with an empty XFixes input shape so DWM does not manage it and clicks pass through it. `mode-osd.service` owns the persistent helper process; `show_*_osd` and `hide_*_osd` scripts should only update state files under `${XDG_RUNTIME_DIR}/dotfiles-mode-osd`. Configure its placement and polling through `DOTFILES_MODE_OSD_OFFSET_X`, `DOTFILES_MODE_OSD_OFFSET_Y`, `DOTFILES_MODE_OSD_ICON_SIZE`, `DOTFILES_MODE_OSD_GAP`, `DOTFILES_MODE_OSD_PADDING`, `DOTFILES_MODE_OSD_POLL_MS`, and `DOTFILES_MODE_OSD_OPACITY`; keep mode indicators out of Dunst because Dunst exposes one global X11 window class/title for all notifications. Readline mode OSD is driven by the system `readline-mode-notify.service` watcher around `keyd listen`; keep that watcher alive and retrying internally when the keyd socket disappears so systemd does not hit `start-limit-hit` during keyd restarts, and have the keyboard-tools handler reset failed state before restarting the unit after template changes. `keyd-observer.service` also uses `Restart=always` for the same reason: mouse mode entry through `Tab+space` depends on that observer staying alive after a keyd restart. Do not reintroduce `cursor_indicator` because its old XQueryPointer polling path made Xorg hot while a mode was active. Keep paired modifier behavior symmetric for MIDI mappings: left and right Shift, Alt/AltGr, and Control should select the same MIDI action. BeatStep-style channel and bank changes are direct selectors rather than increment/decrement keys: hold `o` and press `1`-`8`/`q`-`i` or any pad index to set channel 1-16, or hold `p` and press index 1-4 to set bank 1-4. Smart MIDI entry also uses a single `midi+tab_as_modifier` composite layer: after `Tab+m` turns MIDI mode on, while Tab is still held, `1`-`8`/`q`-`i` selects the initial channel and `a`/`s`/`d`/`f` selects the initial bank. Because `keyd-observer` is a long-running user service, the Arch keyboard-tools task tracks `peripherals/bin/keyd-observer` with a checksum marker and restarts `keyd-observer.service` when the stowed script changes, so applying `10-40` is enough to refresh observer code.
REAPER state feedback that ReaLearn cannot expose should stay scoped to the state source. MIDI-editor-only state belongs in `assets/scripts/reaper/midi_editor_state_feedback.lua`, selected arrange item and item-lane state belongs in `assets/scripts/reaper/item_state_feedback.lua`, project-level transport/options state belongs in `assets/scripts/reaper/project_transport_state_feedback.lua`, and all of them are loaded by `assets/scripts/reaper/__startup.lua`; keep future arrange, project, track, and MIDI-editor state in separate observer scripts instead of expanding one observer across unrelated scopes. Those scripts publish compact `feedback-note` and `feedback-cc` commands to the `keyboard-midi-controller` control socket so the daemon still owns LED matrix and TFT rendering. Do not introduce keyboard-action shadow state for MIDI editor feedback: grid type, grid size, snap, and later MIDI-editor-only states should be derived from REAPER's current editor/take APIs. Some REAPER actions can converge to the same real editor state, such as measure grid and whole-note grid in 4/4, so feedback should represent the state REAPER reports rather than the last action that was pressed.

## Graphic Tablet

Wacom tablet behavior is split between Xorg defaults and runtime reapply hooks:

- Initial driver defaults that must exist before the first proximity event belong under `playbooks/roles/10-system-tools/files/wacom/` and are copied to `/etc/X11/xorg.conf.d/` by the `50-setup-graphic-tablet-tools` task.
- Runtime-only `xsetwacom` actions and settings that depend on current display geometry belong in `peripherals/bin/wacom-config.sh`, which is called by both `wacom.service` and `setup-displays.sh`.
- `utilities/bin/display-health-check` is a manual X11 recovery action for the hybrid display stack. It compares active XRandR outputs with their DRM connector state and forces a small mode refresh when X is still rendering but the kernel reports the panel connector disabled or DPMS-off. It must stay behind the `Tab+Shift+R` keyd signal handled by `peripherals/bin/keyd-observer`; do not run it from a timer or udev rule because routine `xrandr --query` calls can spike Xorg and freeze the session.
- `utilities/bin/setup-displays.sh` owns the local display layout policy and manual laptop/external monitor toggle. XRandR applies the selected laptop-only or external-only layout. `setup-displays.sh --toggle` switches between those layouts from the `Tab+Shift+M` keyd signal handled by `peripherals/bin/keyd-observer`. The return to the laptop panel should enable the internal output as primary at `0x0` and disable the external output in one RandR transaction, then force DPMS on for the internal scanout. Keep this interactive path free of desktop notifications so Plasma does not enter the display-toggle hot path. Avoid always-on polling watchers for monitor power changes; manual keyd-triggered layout changes are preferred because routine display probing can be expensive on this workstation.
- `utilities/bin/apply-wallpaper` is the shared X11 wallpaper entrypoint for `feh.service` and `setup-displays.sh`. Keep `feh` invocation details there so display layout changes can re-apply the root pixmap after monitor connect/disconnect without duplicating directory, image, or X server checks.
- `utilities/bin/x11-monitor-geometry` is the shared helper for monitor-relative runtime geometry. Use it when wrappers need the current monitor's `WxH`, XRandR-style geometry, or ffmpeg `x11grab` input rather than hard-coding a laptop-panel resolution.

## Terminal And Kitty

Kitty configuration belongs in `term/dot-config/kitty/kitty.conf`; helper wrappers and scripts belong under `term/bin/` unless they are editor-specific. The configured `kitty_mod` is `ctrl+shift`, so avoid adding shifted follow-up keys to kitty chord mappings such as `kitty_mod+a>...`. Kitty picker helpers that need cross-process state should use `cachectl` only for rebuildable runtime values such as remote-control sockets, open working directories, or project-directory indexes. Picker startup should prefer cached data first, then fire one immediate background refresh when a list may be stale. That refresh should write the freshly rebuilt data back to `cachectl` before reloading the visible list. When a Kitty picker stays open on an `fzf` list that can change, prefer an `fzf --listen` Unix socket plus a one-shot background reload so the visible list can update without restarting the picker. Avoid `fzf --track` for these one-shot reload pickers unless there is a specific need to preserve cursor identity across reloads; it can leave the highlighted row offset from the active query after the reload lands. Kitty `fzf` pickers and quick-access TUIs that need their own OS window should launch through `kitten quick-access-terminal`, inherit the shared `quick-access-terminal.conf`, and keep per-picker overrides limited to sizing or identity values such as `lines`, `app_id`, and `background_opacity`. Keep the launcher path thin: create only the temporary paths needed to collect the result before invoking `quick-access-terminal`, then read caches and build the initial `fzf` choices inside the panel command so the OS window appears before rebuildable data work begins.

Kitty quick-access-terminal uses Kitty's panel machinery internally. On X11, the default `edge top` panel geometry forces full monitor width after DWM applies float rules, so DWM-managed quick-access windows should use `edge none`. DWM float geometry rules for these windows rely on the local floatrules preservation patch in the DWM patch stack. When a quick-access TUI should cover the active monitor regardless of display size, use the DWM `FULLMON` float rule sentinel instead of hard-coded pixel dimensions.

Quick-access TUI wrappers should scope panels per Kitty OS window with `--instance-group`. Use an app-specific prefix, such as `nnn-$KITTY_OS_INSTANCE_ID`, when the app must coexist with another quick-access terminal in the same OS window.

For app-specific kitty macros, prefer scoping the window at launch with `--var=...` and binding with `map --when-focus-on var:...`. When a single key needs stateful toggle behavior, a kitty user var updated via `remote_control set-user-vars` can keep the state local to that window without adding a helper script.

### Kitty User Var Naming Convention

Kitty user vars are for window-local state, not for identifying which app a window is running. Focus helpers, `map --when-focus-on`, and `kitten @ focus-window --match` should prefer `cmdline:<process>` matching for app identity so stale user vars cannot outlive the process that set them.

- Use `<app>_<attribute>` (snake_case) for app-scoped state attached to a window. Examples in use: `lazygit_preview_fullscreen`, `lazy_started`.
- Use `"1"` and `""` (or `"0"`) for booleans so `var:name=1` and `not var:name=1` work as expected. `--var=name` with no value is treated as truthy by Kitty, but prefer the explicit `name=1` form so the same string can be matched in `jq` over `user_vars`.
- Lifecycle-pair every state var that mirrors transient UI state: whatever sets it should also clear it when the state ends, so the value does not mislead later bindings in the same Kitty window.

Shared kitty window helpers (focus matching, JSON scoring, etc.) live in `term/bin/kitty-window-utils.sh`. Source it from POSIX sh and pass process names for app identity. App-specific focus helpers belong to the owning script.

Launch `nnn` through `term/bin/nnn-with-defaults` instead of repeating its standard flags or `NNN_*` environment. Use `--open-in-nvim` for Kitty panels or Neovim tasks that should route file opens back through `open_in_nvim`. The quick-access `nnn` panel sets `KITTY_NNN_QUICK_ACCESS=1`; Kitty mappings that are specific to that panel should match this environment variable so they do not affect ordinary `nnn` processes. `term/bin/kitty-nnn-quick-access` keeps an existing panel when its nnn child is already in the requested directory, and uses the hidden `;c` plugin path when a real file path requires a different directory. That path stores the target directory in runtime state, sends the plugin key through the panel's own Kitty remote-control socket, and lets `term/bin/nnn-quick-access-cd` write `0c<dir>` to `NNN_PIPE` while nnn is actively reading plugin control messages. Pass startup paths as nnn's positional `PATH`; `-c` is nnn's CLI-opener option, not a directory-changing option. Interactive Bash shells spawned from `nnn` still load the normal shell features, including ble.sh. Keep nnn-specific Bash hooks guarded by `NNN_PIPE` and tolerate a missing or closed pipe so transient nnn shells do not report exit-time pipe errors. ble.sh customizations live in `home/dot-blerc`. The local history helper override avoids `history | ... q` pipelines because Bash can report `history: write error: Broken pipe` when a large history is piped to a consumer that exits after the first line.

See [nvim-kitty-integration.md](./nvim-kitty-integration.md) for the per-window Neovim server socket and Kitty window matching that exercise this convention end to end.

## Window Manager

dwm is built from upstream plus local patches. Most behavior changes belong in patch files under:

```text
playbooks/roles/10-system-tools/files/
```

The compositor/window-manager setup task is:

```text
playbooks/roles/10-system-tools/tasks/100-setup-compositor.archlinux.yml
```

DWM float rules support the local `FULLMON` sentinel for windows that should fill the selected monitor while remaining floating. Keep monitor-relative fullscreen behavior in the DWM patch stack rather than encoding a specific panel resolution such as `1920x1080`.

## Existing Documentation

Specific operational notes live in `docs/`, including keyd setup, NVIDIA setup, Neovim debugging, Python development setup, and hardware-specific notes. Prefer adding focused docs there instead of expanding the root README with long implementation details.

- Browser launcher resource limits are documented in [browser-resource-limits.md](./browser-resource-limits.md).
- Wine app launcher logging and user-level logrotate ownership are documented in [wine-app-logging.md](./wine-app-logging.md).
- Realtime kernel migration notes for the Secure Boot, TPM, NVIDIA DKMS, and VirtualBox DKMS switch are documented in [realtime-kernel-migration.md](./realtime-kernel-migration.md).

## KDE Runtime Configuration

KDE global shortcut settings are tracked in `utilities/dot-config/kglobalshortcutsrc`, which is stowed to `~/.config/kglobalshortcutsrc`. The active KDE session reads these shortcuts through the user `plasma-kglobalaccel.service`; do not update that live state by hand during normal maintenance. The Arch dotfiles task records a checksum for the tracked shortcut file under `~/.local/state/dotfiles/` and restarts `plasma-kglobalaccel.service` only when that checksum changes. In the DWM session there is no full Plasma panel, so the KDE clipboard UI is loaded by `utilities/dot-config/systemd/user/plasma-clipboard.service`, which runs `plasmawindowed --statusnotifier org.kde.plasma.clipboard`. The dotfiles task enables and starts that user service after stowing `utilities`, and restarts it only when the tracked unit file checksum changes.

Screenshot capture is owned by Spectacle's `RectangularRegionScreenShot` global shortcut in `utilities/dot-config/kglobalshortcutsrc`. Do not restore Flameshot as the default screenshot tool in the DWM session: recent Flameshot builds route capture through the KDE portal, which expects the `org.kde.KWin` D-Bus service and fails when KWin is intentionally replaced by DWM.

When KWallet reports a GPG decrypt failure such as `No secret key` but no pinentry dialog appears, first check whether `keyboxd` is waiting on a stale GnuPG lock held by `ksecretd`. The `utilities/bin/kwallet-fix` helper is the short recovery command for this state: it stops the transient KDE Secret Service compatibility unit and `kwalletd6` unit so D-Bus can relaunch them cleanly, then reloads kded's `networkmanagement` module so pending NetworkManager secret requests stop using stale wallet state, without restarting the whole session.

XDG app autostarts are disabled for the user session by masking the systemd XDG autostart generator globally with `/etc/systemd/user-generators/systemd-xdg-autostart-generator -> /dev/null` when Ansible can become root. Do not mask `xdg-desktop-autostart.target` itself: Plasma's systemd boot wants that target, and masking it can make Plasma fall back to the classic startup path where KWin is launched outside systemd. Keep session startup intentional through dotfiles-owned user systemd units such as `plasma-wm.service` and `compositor.service`; package-provided `.desktop` autostarts should not create generated `app-*@autostart.service` units.
