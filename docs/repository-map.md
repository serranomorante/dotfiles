# Repository Map

This map describes where changes usually belong. It is intentionally practical:
start here when deciding which file owns a behavior.

## Top-Level Packages

- `playbooks/`: Ansible entrypoints, roles, templates, filters, and local
  modules.
- `peripherals/`: keyboard, mouse, tablet, keyd, mouseless, warpd, and related
  user services/scripts.
- `nvim/`: Neovim config and wrappers.
- `term/`: terminal wrappers, Kitty-related tooling, and tmux configuration.
- `systemd/`: user-level systemd units that are not tied to a narrower package.
- `audio/`: audio production and routing configuration/scripts.
- `utilities/`: general user scripts and utility configs.
- `dunst/`: notification daemon configuration.
- `lazygit/`: lazygit configuration. See [lazygit.md](./lazygit.md) for pager
  and diff setup.
- `home/`: generic home-directory dotfiles.
- `PKM/`: personal knowledge management tooling.
- `assets/`: static assets, patches, scripts, services, udev rules, and media.
- `docs/`: human-readable operational notes and project context.
- `for-my-eyes-only/`: optional private package and submodule. Do not touch
  unless explicitly requested. Package-specific private assistant context should
  live at `for-my-eyes-only/docs/agent-context.md`; the public Ansible role
  links shared agent entrypoints into this package when it exists.

## Ansible Structure

The main playbook is `playbooks/tools.yml`. It gathers facts, detects some host
state, then imports roles in numeric order. Roles use numeric task filenames to
make execution order visible.

```text
playbooks/roles/10-system-tools/
playbooks/roles/20-dev-tools/
playbooks/roles/30-lang-tools/
playbooks/roles/40-PKM/
playbooks/roles/50-cloud-tools/
```

Common patterns:

- OS-specific task files use suffixes such as `.archlinux.yml`, `.debian.yml`,
  `.otherlinux.yml`, and `.macosx.yml`.
- Role task files are included through `with_first_found`, so missing OS files
  can be valid.
- Role tags follow the role/task number, such as `10-40` or `20-90`.
- Templates live under `playbooks/roles/<role>/templates/`.
- Patches used by playbooks usually live under `playbooks/roles/<role>/files/`
  or `assets/patches/`.

## Stow Model

Dotfile packages are stowed from the repository root. Public packages are
applied in `10-system-tools/tasks/30-setup-dotfiles.*.yml`.

Important conventions:

- Use `dot-*` names for files/directories that should become hidden dotfiles.
- Keep each top-level package focused on one area of the system.
- `.stow-local-ignore` files prevent irrelevant files from being linked into
  `$HOME`.
- Stow is invoked through the generated `~/bin/dotfiles-stow` wrapper, which
  applies `dotfiles_stow_options` and `dotfiles_stow_ignore_patterns` from the
  `10-system-tools` defaults, plus the configured agent context filenames. The
  wrapper always changes to the generated user's `~/dotfiles` before invoking
  Stow, so it can be run from any directory.
- Private packages are listed separately in `dotfiles_private_stow_packages`.
  `for-my-eyes-only/docs/agent-context.md` is also ignored by the wrapper so
  private AI notes can remain in the package without being linked into `$HOME`.
- Existing symlinked files update in place when edited in the repository, but
  newly added files under a stowed package are not active until that package is
  stowed again. For example, after adding a file under `nvim/`, run
  `~/bin/dotfiles-stow nvim` or include the dotfile setup task in the next
  Ansible run.

## Neovim

Task-runner and job-management modules belong under
`nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/`. Runtime plugin
entrypoints under `nvim/dot-config/nvim/plugin/` should only load those modules.

## Shared Runtime Cache

Use Valkey for small cross-process runtime caches that need to be shared by
Neovim, Kitty helpers, shell scripts, or Python scripts. `utilities/bin/cachectl`
wraps `valkey-cli` with the repository key namespace
`dotfiles:cache:v1:<namespace>:<key>` and requires TTLs for stored values.
Values should be cheap to rebuild and should not be committed.

## Dev Tool Sandboxing

Python and Node package-manager installs and routine tool execution should use
the Firejail wrappers owned by `playbooks/roles/20-dev-tools/`. See
[firejail-dev-tools.md](./firejail-dev-tools.md) for wrapper contracts,
Ansible adapter examples, network modes, and profile guidance.

## Voice TTS Workflows

Text-to-speech wrappers for narrating terminal commands, TUIs, and AI CLIs
live in `utilities/bin/` and are documented in
[voice-agent-workflows.md](./voice-agent-workflows.md). The baseline path
should stay usable from a plain TTY, so prefer official Arch packages such as
`speech-dispatcher` and `espeak-ng` over optional AUR neural TTS engines for
the fallback layer.

## REAPER

REAPER scripts that should be managed by Ansible live in
`assets/scripts/reaper/`. Native Linux REAPER startup hooks are installed from
`assets/scripts/reaper/__startup.lua` by the `10-120` wine-tools task into
`~/.config/REAPER/Scripts/__startup.lua`; keep per-feature startup logic in
separate files under `Scripts/custom/` and load them from that entrypoint.
WineASIO for Windows REAPER is built by the same `10-120` wine-tools task from
`wine-tools/wineasio.task.yml`, installed into both the managed portable Wine
tree and system Wine tree, and registered into the Reaper Wine prefix.

## Keyboard And Mouse-Free Workflow

The keyboard/mouse stack is split across keyd, a small observer script, warpd,
and mouseless.

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

mouseless config
  owns keyboard-driven mouse movement and mouse buttons
```

`warpd-marker` and `warpd-trail` compile their embedded X11 helpers into stable
cache paths under `~/.cache`. Do not bump helper filenames for code changes; the
wrappers compare the generated C source with the cached source and rebuild when
needed. The keyboard-tools Ansible task precompiles the stable helpers.

When fixing keyboard conflicts, first identify who consumes the key:

- keyd mapping
- mouseless mouse layer
- warpd mode
- dwm binding
- application-level shortcut

Then prefer the smallest translation at the layer that already owns similar
conflicts.
If a KDE global shortcut overlaps a keyd modifier layer, prefer moving it to a
non-`Meta` chord such as `Ctrl+Alt+V` before adding passthroughs. Plain
`Meta+V` and `Meta+C` are owned by keyd's Gromit bindings.
In the DWM session, `Ctrl+Alt+V` is owned by keyd and handled by
`keyd-observer`, which calls Klipper's `org.kde.klipper.klipper.showKlipperPopupMenu`
D-Bus method directly. Do not also bind that chord in KDE global shortcuts.
Because `keyd-observer` is a long-running user service, the Arch dotfiles task
tracks `peripherals/bin/keyd-observer` with a checksum marker and restarts
`keyd-observer.service` when the stowed script changes.

## Graphic Tablet

Wacom tablet behavior is split between Xorg defaults and runtime reapply hooks:

- Initial driver defaults that must exist before the first proximity event
  belong under `playbooks/roles/10-system-tools/files/wacom/` and are copied to
  `/etc/X11/xorg.conf.d/` by the `50-setup-graphic-tablet-tools` task.
- Runtime-only `xsetwacom` actions and settings that depend on current display
  geometry belong in `peripherals/bin/wacom-config.sh`, which is called by both
  `wacom.service` and `setup-displays.sh`.

## Terminal And Kitty

Kitty configuration belongs in `term/dot-config/kitty/kitty.conf`; helper
wrappers and scripts belong under `term/bin/` unless they are editor-specific.
The configured `kitty_mod` is `ctrl+shift`, so avoid adding shifted follow-up
keys to kitty chord mappings such as `kitty_mod+a>...`.
Kitty picker helpers that need cross-process state should use `cachectl` only
for rebuildable runtime values such as remote-control sockets, open working
directories, or project-directory indexes. Picker startup should prefer cached
data first, then fire one immediate background refresh when a list may be stale.
That refresh should write the freshly rebuilt data back to `cachectl` before
reloading the visible list.
When a Kitty picker stays open on an `fzf` list that can change, prefer an
`fzf --listen` Unix socket plus a one-shot background reload so the visible list
can update without restarting the picker.
Avoid `fzf --track` for these one-shot reload pickers unless there is a specific
need to preserve cursor identity across reloads; it can leave the highlighted
row offset from the active query after the reload lands.
Kitty `fzf` pickers and quick-access TUIs that need their own OS window should
launch through `kitten quick-access-terminal`, inherit the shared
`quick-access-terminal.conf`, and keep per-picker overrides limited to sizing
or identity values such as `lines`, `app_id`, and `background_opacity`.
Keep the launcher path thin: create only the temporary paths needed to collect
the result before invoking `quick-access-terminal`, then read caches and build
the initial `fzf` choices inside the panel command so the OS window appears
before rebuildable data work begins.

Kitty quick-access-terminal uses Kitty's panel machinery internally. On X11,
the default `edge top` panel geometry forces full monitor width after DWM
applies float rules, so DWM-managed quick-access windows should use
`edge none`. DWM float geometry rules for these windows rely on the local
floatrules preservation patch in the DWM patch stack.

Quick-access TUI wrappers should scope panels per Kitty OS window with
`--instance-group`. Use an app-specific prefix, such as
`nnn-$KITTY_OS_INSTANCE_ID`, when the app must coexist with another
quick-access terminal in the same OS window.

For app-specific kitty macros, prefer scoping the window at launch with
`--var=...` and binding with `map --when-focus-on var:...`. When a single key
needs stateful toggle behavior, a kitty user var updated via `remote_control
set-user-vars` can keep the state local to that window without adding a helper
script.

### Kitty User Var Naming Convention

Kitty user vars are for window-local state, not for identifying which app a
window is running. Focus helpers, `map --when-focus-on`, and
`kitten @ focus-window --match` should prefer `cmdline:<process>` matching for
app identity so stale user vars cannot outlive the process that set them.

- Use `<app>_<attribute>` (snake_case) for app-scoped state attached to a
  window. Examples in use: `lazygit_preview_fullscreen`, `lazy_started`.
- Use `"1"` and `""` (or `"0"`) for booleans so `var:name=1` and `not
  var:name=1` work as expected. `--var=name` with no value is treated as
  truthy by Kitty, but prefer the explicit `name=1` form so the same string
  can be matched in `jq` over `user_vars`.
- Lifecycle-pair every state var that mirrors transient UI state: whatever
  sets it should also clear it when the state ends, so the value does not
  mislead later bindings in the same Kitty window.

Shared kitty window helpers (focus matching, JSON scoring, etc.) live in
`term/bin/kitty-window-utils.sh`. Source it from POSIX sh and pass process
names for app identity. App-specific focus helpers belong to the owning
script.

Launch `nnn` through `term/bin/nnn-with-defaults` instead of repeating its
standard flags or `NNN_*` environment. Use `--open-in-nvim` for Kitty panels or
Neovim tasks that should route file opens back through `open_in_nvim`.
The quick-access `nnn` panel sets `KITTY_NNN_QUICK_ACCESS=1`; Kitty mappings
that are specific to that panel should match this environment variable so they
do not affect ordinary `nnn` processes.
Interactive Bash shells spawned from `nnn` still load the normal shell features,
including ble.sh. Keep nnn-specific Bash hooks guarded by `NNN_PIPE` and tolerate
a missing or closed pipe so transient nnn shells do not report exit-time pipe
errors.
ble.sh customizations live in `home/dot-blerc`. The local history helper
override avoids `history | ... q` pipelines because Bash can report
`history: write error: Broken pipe` when a large history is piped to a consumer
that exits after the first line.

See [nvim-kitty-integration.md](./nvim-kitty-integration.md) for the
per-window Neovim server socket and Kitty window matching that exercise this
convention end to end.

## Window Manager

dwm is built from upstream plus local patches. Most behavior changes belong in
patch files under:

```text
playbooks/roles/10-system-tools/files/
```

The compositor/window-manager setup task is:

```text
playbooks/roles/10-system-tools/tasks/100-setup-compositor.archlinux.yml
```

## Existing Documentation

Specific operational notes live in `docs/`, including keyd setup, NVIDIA setup,
Neovim debugging, Python development setup, and hardware-specific notes. Prefer
adding focused docs there instead of expanding the root README with long
implementation details.

- Browser launcher resource limits are documented in
  [browser-resource-limits.md](./browser-resource-limits.md).

## KDE Runtime Configuration

KDE global shortcut settings are tracked in
`utilities/dot-config/kglobalshortcutsrc`, which is stowed to
`~/.config/kglobalshortcutsrc`. The active KDE session reads these shortcuts
through the user `plasma-kglobalaccel.service`; do not update that live state by
hand during normal maintenance. The Arch dotfiles task records a checksum for
the tracked shortcut file under `~/.local/state/dotfiles/` and restarts
`plasma-kglobalaccel.service` only when that checksum changes.
In the DWM session there is no full Plasma panel, so the KDE clipboard UI is
loaded by `utilities/dot-config/systemd/user/plasma-clipboard.service`, which
runs `plasmawindowed --statusnotifier org.kde.plasma.clipboard`. The dotfiles
task enables and starts that user service after stowing `utilities`, and
restarts it only when the tracked unit file checksum changes.
