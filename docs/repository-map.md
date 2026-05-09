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
- `for-my-eyes-only/`: optional private package. Do not touch unless explicitly
  requested.

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

For app-specific kitty macros, prefer scoping the window at launch with
`--var=...` and binding with `map --when-focus-on var:...`. When a single key
needs stateful toggle behavior, a kitty user var updated via `remote_control
set-user-vars` can keep the state local to that window without adding a helper
script.

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
