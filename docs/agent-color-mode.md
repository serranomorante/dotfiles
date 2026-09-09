# Agent Color Mode

The KDE color scheme is the single source of truth for light/dark on this workstation. kitty follows it natively through its `*-theme.auto.conf` files, and Neovim is pushed the mode by `utilities/bin/dbus_listen_color_change` (installed as `~/bin/dbus_listen_color_change` and run by `subscribe_color_change.service`). The terminal AI agents follow the same switch, but each one needs a different mechanism because they expose very different theming contracts.

## Ownership

- `utilities/bin/agent-color-mode` resolves the mode (`ColorScheme` in `kdeglobals`, or an explicit `light`/`dark` argument) and writes the agent config fragments that cannot follow the terminal on their own.
- `utilities/bin/dbus_listen_color_change` seeds `agent-color-mode` once at service start and then calls it on every portal `ColorScheme` signal, next to the existing Neovim push.
- `playbooks/roles/20-dev-tools/tasks/170-setup-ai-tools.archlinux.yml` owns the declarative half: the Claude Code `theme` setting, the Gemini CLI `ui` block, and the OpenCode theme file. It also seeds `agent-color-mode` so a fresh install is correct before the next login.

## Per-agent Mechanism

- **Claude Code** reads `theme` at startup only, so a plain `light`/`dark` value would never reach a running session. Instead `theme` is pinned to `custom:dotfiles-system` (`claude_global_settings_config` in `playbooks/roles/20-dev-tools/defaults/main/ai.yml`) and `agent-color-mode` rewrites `~/.claude/themes/dotfiles-system.json`, flipping only its `base` between the stock `light` and `dark` palettes. Claude Code watches that directory and reloads custom themes, so running sessions repaint. The file is replaced only when the mode actually changes, so unrelated writes never wake the watcher. Custom themes are disabled in safe mode, where Claude Code falls back to its dark palette.
- **Codex** renders its own chrome from the terminal palette, so it follows kitty without help. Only the syntect theme used for code and diffs is pinned, so `agent-color-mode` maintains a marked root-level `tui.theme` key in `~/.codex/config.toml` and flips it between `base16-ocean.dark` and `base16-ocean.light`. TOML requires that dotted key ahead of every table header, and a `[tui]` table written by Codex itself would make it a duplicate key, so the script leaves such a file untouched and logs why. Codex reads `config.toml` at startup, so this applies to new sessions.
- **Gemini CLI** polls the terminal background (`ui.terminalBackgroundPollingInterval`, lowered to 5 seconds here) and picks its default light or dark theme from it when `ui.autoThemeSwitching` is on. That detection only runs while `ui.theme` is unset, so the Ansible task removes a pinned `ui.theme` instead of merging over it, and nothing is written at runtime.
- **OpenCode** detects light/dark from the terminal palette itself and resolves per-mode theme values, so `opencode_dotfiles_system_theme.json.j2` declares every color as a `{"dark": ..., "light": ...}` pair and `background` stays `none` so the terminal background shows through. Nothing is written at runtime.
- **Pi** ships built-in `dark`/`light` themes and detects the terminal background on first run, so the Neovim launcher starts it with `--use-theme light/dark`, which makes each Pi session follow the terminal appearance (driven by kitty -> KDE) without persisting a pinned theme. Nothing is written at runtime.

## Applying and Verifying

`agent-color-mode` and `dbus_listen_color_change` are Stow-managed, so a changed script needs `dotfiles-stow utilities` plus a restart of `subscribe_color_change.service` before the running listener picks it up. Never `disable`/`reenable` that unit: it is a Stow symlink and systemd deletes the link.

To check the current state without switching the desktop theme, run `agent-color-mode light` or `agent-color-mode dark` and inspect `~/.claude/themes/dotfiles-system.json` and the marked block in `~/.codex/config.toml`. `tests/utilities/agent_color_mode.sh` covers detection, the no-op write guard, the Codex marker block, and the `[tui]` table bail-out.

## Known Issue: `997;Nn` Text Leaking Into An Agent's Input

When an agent runs as kitty → Neovim builtin terminal → tmux → agent, every system color scheme change can leave literal text such as `997;2n` (light) or `997;1n` (dark) in the agent's input box, one fragment per switch. It is cosmetic: the bytes land in the composer as text and clearing the line removes them. The color switch itself is unaffected, and `agent-color-mode` is not involved — it only writes files and emits no escape sequences.

These are near-miss DEC private mode 2031 theme-change reports. The spec form is `CSI ? 997 ; N n`, but Neovim's builtin terminal sends it without the private-mode `?`: the format string in its `term->pending.send` path is `\033[997;%cn`, while a separate correct `?997;%cn` literal exists elsewhere in the same binary. **The missing `?` is the fingerprint**: kitty and tmux both emit only the `?` forms, so leaked text without a `?` identifies Neovim's builtin terminal as the emitter rather than the outer terminal.

Nothing downstream recognizes that variant. tmux requests mode 2031 from whatever terminal hosts it, unconditionally as part of its startup sequence (`[?2031h` followed by `[?996n`), so a tmux nested inside a Neovim terminal receives the malformed report on every Neovim `background` change and passes the unrecognized bytes to the pane. Claude Code's parser is anchored on the `?` form (`/^\x1b\[\?997;([12])n$/`), so the report falls through to the text path with `ESC [` stripped.

There is no clean local switch. tmux exposes no `terminal-features` flag for theme reporting, and the mode is requested by tmux rather than by the agent, so it cannot be turned off from the agent side either. The real fix belongs upstream in Neovim; the only local alternative is not nesting tmux inside the Neovim terminal for agent panes.

Recorded against Neovim `v0.13.0-dev-1556+g9f425311c3`, tmux `3.7c`, and `@anthropic-ai/claude-code` `2.1.261`. The chain above is inferred from byte-level inspection of those binaries plus the missing `?` in the observed text; it was not reproduced end to end, because a synthetic tmux input-injection harness failed to deliver even plain keystrokes to the pane. Re-verify the Neovim format string before assuming this still applies after a Neovim update.
