# DWM Scratchpad Terminal

A global quick-access terminal for running quick commands from anywhere, toggled by a dwm key instead of a kitty keymap.

The scratchpad is a plain-shell Kitty panel with no specific application. It is opened and hidden from dwm (`MODKEY+Shift+Return`), so it works from any application, not only inside Kitty. It uses the same quick-access-terminal kitten as `kitty-lazygit-quick-access` and `kitty-nnn-quick-access`, so the panel stays loaded in the background between toggles instead of closing.

## Ownership

- Wrapper: `term/bin/kitty-scratchpad-quick-access` (stowed to `~/bin/kitty-scratchpad-quick-access`).
- Kitty panel settings: shared `term/dot-config/kitty/quick-access-terminal.conf` (`edge none`, `hide_on_focus_loss yes`).
- DWM wiring: `playbooks/roles/10-system-tools/files/custom.patch` (float rule, `scratchcmd`, key binding) and `add-dwm-scratchpad-hide-on-close.patch` (hide instead of kill on `MODKEY+Shift+C`).
- Test: `tests/term/kitty_scratchpad.sh`.

## How it works

The wrapper invokes the kitten with a fixed `--instance-group="scratchpad"`, unlike the per-Kitty-window wrappers that scope panels to `KITTY_OS_INSTANCE_ID`. A fixed group keeps one scratchpad shared across the desktop: the first invocation starts the panel and a plain shell inside it, and later invocations toggle that same panel's visibility without killing the shell.

The panel is created with `--override app_id=kitty-scratchpad`, which sets its X11 `WM_CLASS`. DWM matches that class in `custom.patch` to float the window full-monitor (`FULLMON`) and skip it in focus history, mirroring the existing `kitty-lazygit`/`kitty-nnn` quick-access rules.

`hide_on_focus_loss yes` gives the scratchpad dropdown behavior: focusing any other window hides it while the shell stays alive.

`MODKEY+Shift+Return` reaches dwm through keyd, which intercepts keys at the kernel level: `[meta+shift]` in the keyd template must map `enter = M-S-enter` instead of launching kitty, otherwise keyd swallows the chord before dwm sees it.

`add-dwm-scratchpad-hide-on-close.patch` special-cases dwm's `killclient`: when the focused window is the scratchpad (WM_CLASS `kitty-scratchpad`), it spawns the toggle command instead of sending `WM_DELETE`, so `MODKEY+Shift+C` hides the panel and preserves the shell and its history rather than killing the process. The shell can still be truly closed by exiting it (Ctrl+D).

## Applying changes

New code is stowed with `dotfiles-stow term`. DWM changes need a rebuild: because `custom.patch` or the dwm.c hide-on-close patch changed, bump the `dwm_patch_marker` contract (`patch-stack-v11` in `100-setup-compositor.archlinux.yml`) so the next compositor run re-clones, re-patches, and reinstalls dwm.
