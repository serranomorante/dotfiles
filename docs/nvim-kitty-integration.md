# Neovim And Kitty Integration

The Neovim/Kitty integration gives each working directory a predictable Kitty remote-control socket and a directly corresponding Neovim server socket. Neovim owns the Kitty focus handoff when a remote client opens or displays a buffer in that server.

## CWD-Derived Socket Pair

`term/bin/kitty` starts each Kitty UI window with a fresh `KITTY_OS_INSTANCE_ID` for Kitty-specific grouping, and a cwd-derived `KITTY_LISTEN_ON` remote-control socket. Launchers that open a specific directory, such as `term/bin/kitty-dmenu`, should provide `KITTY_LISTEN_ON` from the selected target cwd before invoking `kitty -d`, because the wrapper's own process cwd may be different from the target directory.

The Kitty socket path lives under `$XDG_RUNTIME_DIR` and uses this readable pattern:

```text
unix:$XDG_RUNTIME_DIR/kitty-cwd-<absolute-cwd-with-slashes-as-__>.sock
```

Neovim does not listen on the same socket, because Kitty and Neovim speak different protocols and cannot both bind the same path. Instead, the Neovim server socket is derived from the Kitty socket by replacing `.sock` with `.nvim.sock`:

```text
$XDG_RUNTIME_DIR/kitty-cwd-<absolute-cwd-with-slashes-as-__>.nvim.sock
```

The leading slash is omitted from the socket filename, and characters outside `A-Za-z0-9._-` are replaced with `_`.

For example, a Kitty launched from `/home/aaaa/dotfiles/playbooks` targets:

```text
KITTY_LISTEN_ON=unix:$XDG_RUNTIME_DIR/kitty-cwd-home__aaaa__dotfiles__playbooks.sock
Neovim server=$XDG_RUNTIME_DIR/kitty-cwd-home__aaaa__dotfiles__playbooks.nvim.sock
```

The cwd-derived Kitty socket is also the discovery key for the UI window, so `term/bin/kitty-dmenu` can enumerate `$XDG_RUNTIME_DIR/kitty-cwd-*.sock` directly instead of discovering Kitty processes. The corresponding Neovim server socket keeps external tools able to call either `open_in_nvim --cwd <cwd>` or `open_in_nvim --servername <socket>` without discovering a random per-window UUID first. `--cwd .` resolves to the caller's current working directory before deriving the socket name.

Neovim local persistence is gated by the cwd-derived server socket, but durable state filenames are keyed by the working directory. Keep ShaDa and similar local state resilient to socket naming changes: the server name decides whether local state is enabled, not which saved state file belongs to a cwd.

The `nvim/bin/nvim` wrapper uses that socket to either reuse an existing Neovim server or start a new listening server in the same Kitty window. It stays out of the way for explicit client-server invocations (`--server`, `--listen`, `--remote*`, `--headless`).

Kitty mappings that need a standalone Neovim UI in the newly launched Kitty window, such as scrollback-pager overlays, should clear `KITTY_LISTEN_ON` for that launch. Otherwise the wrapper may treat the pager process as a client of the cwd-derived server and redirect it into an existing Neovim window.

## Kitty Window Matching

While an interactive Neovim process is alive in a Kitty window, Kitty exposes that process through the window cmdline / foreground-process data. The focus helpers use that process data as the app identity signal.

`lazygit` is launched through Kitty's quick-access-terminal kitten. The panel behavior lives in `term/dot-config/kitty/quick-access-terminal.conf`, and every entry point toggles it through the shared `term/bin/kitty-lazygit-quick-access` wrapper. The wrapper invokes the kitten with `--instance-group="$KITTY_OS_INSTANCE_ID"`, so each Kitty OS window manages an independent panel. `hide_on_focus_loss yes` lets Kitty hide the panel when the remote edit shifts focus back to Neovim.

The main Kitty config binds `kitty_mod+s` to a Kitty background launch of the wrapper, which is the single user-facing toggle for the panel.

`nnn` also runs through Kitty's quick-access-terminal kitten, via `term/bin/kitty-nnn-quick-access`. The wrapper uses `nnn-<role>-$KITTY_OS_INSTANCE_ID` instance groups so the session-wide nnn panel and the Neovim-owned nnn panel are independent inside the same Kitty OS window. The default role is `session`, which is what `kitty_mod+r` uses. Neovim's `<leader>e` binding sets `KITTY_NNN_INSTANCE_ROLE=nvim`, invokes the same wrapper with the current buffer path only when the buffer is backed by a real file, and lets `open_in_nvim` recover the matching Neovim server from the existing Kitty process context instead of embedding nnn in an Overseer terminal float. When a real file path is provided, the wrapper compares the target directory with the existing nnn child process' current working directory. If they match, it keeps the existing quick-access nnn state and just toggles the panel. If they differ, it writes a target file under `${XDG_RUNTIME_DIR:-/tmp}/nnn-quick-access` for that Neovim-owned panel and sends nnn's `;c` plugin key through the panel's own Kitty remote-control socket. That runs `term/bin/nnn-quick-access-cd`, which writes nnn's `0c<dir>` control message to `NNN_PIPE` while nnn is actively running a plugin, avoiding a panel restart. New `nnn` processes receive the current file or directory as nnn's positional `PATH`; do not pass it with `-c`, because in nnn `-c` configures the CLI opener. Relaunches from inside the nnn panel must preserve `KITTY_NNN_INSTANCE_GROUP` or recover the group from `NNN_QUICK_ACCESS_TARGET`; recalculating it from the panel's own `KITTY_OS_INSTANCE_ID` creates another panel instead of toggling the original one. Buffers without a real file path call the wrapper without a path, so the existing nnn state is preserved. Keep `nnn-with-defaults --open-in-nvim` on this path so file opens and the nnn `Find`/`Grep` plugins continue to target the active Neovim server through `open_in_nvim`. `NNNSearch` explicitly calls the remote Kitty focus helper after writing `:Find`/`:Grep` into Neovim's command line, because that handoff does not necessarily enter a new buffer and therefore cannot rely only on the remote-edit `BufEnter` focus autocmd.

## Remote Edit Focus Handoff

`nvim/dot-config/nvim/lua/serranomorante/remote_kitty_focus.lua` owns this stateful handoff and is loaded from `serranomorante/init.lua`. It watches `ChanOpen` for remote RPC clients on the per-window server socket. When a later `BufEnter` or `BufWinEnter` follows shortly after that remote connection, Neovim checks whether its own `$KITTY_WINDOW_ID` is already focused. If not, it runs `kitten @ focus-window --match id:$KITTY_WINDOW_ID`. That check must confirm the parent tab is active, not only that the window has `is_focused=true`; Kitty can report active windows from inactive tabs that way inside the focused OS window state.

The follow-up buffer/window event is intentional: background RPC commands that only evaluate expressions or update state, such as color-mode broadcasts, should not steal focus. Remote edits from `nvr`, native `nvim --server --remote`, and `--remote-send` commands that open a buffer do trigger the handoff.

## Helpers

Shared, generic kitty window helpers live in `term/bin/kitty-window-utils.sh` (sourced library, POSIX sh):

- `kitty_nvim_servername_from_context` — resolve the matching Neovim server from a valid cwd-derived `KITTY_LISTEN_ON`, then `KITTY_PID`, then cwd.
- `kitty_nvim_servername_from_listen_on ADDRESS` — convert a Kitty `unix:/path/to/kitty-cwd-*.sock` address to the matching `.nvim.sock` path. Other Kitty remote-control sockets are intentionally ignored because panels such as nnn can expose their own local `KITTY_LISTEN_ON`.
- `kitty_nvim_servername_from_pid PID` — read a Kitty process environment and derive the matching Neovim server from its `KITTY_LISTEN_ON`.
- `kitty_nvim_servername_from_cwd CWD` — derive the cwd-based Neovim socket.
- `kitty_nvim_servername_from_kitty_context` — resolve from a valid `KITTY_LISTEN_ON` or `KITTY_PID` without falling back to cwd.
- `kitty_focus_match QUERY` — wraps `kitten @ focus-window --match`.
- `kitty_focus_window_id ID` — focus by numeric Kitty window id.
- `kitty_focused_os_windows_json` — emit the focused-OS-window subset of `kitten @ ls`.
- `kitty_target_window_id PROCESS_NAME` — search across the focused OS window's tabs by cmdline / foreground processes. On ties, the more recently focused window wins.

App-specific focus helpers live in the owning script. For the Neovim/lazygit handoff, `nvim/bin/open_in_nvim` sends the remote edit directly to the CWD-derived Neovim server. Neovim's autocmd focuses the Neovim Kitty window after the remote edit displays a buffer, and Kitty's quick-access-terminal configuration hides the lazygit panel on focus loss. Showing the panel is owned by the `kitty_mod+s` binding in `kitty.conf`; the shell script no longer exposes a `focus_lazygit` entry point.

A cache is intentionally avoided in any of these helpers because the focused Kitty window state is small, cheap to query, and easy to make stale.

## Consumers

- `nvim/bin/open_in_nvim` sends remote edit requests to the configured Neovim server. It defaults to the server derived from a valid cwd-based `KITTY_LISTEN_ON`, accepts `--cwd <cwd>` to derive the predictable CWD socket, and accepts `--servername <socket>` when a tool already knows the exact server socket. If the caller's `KITTY_LISTEN_ON` is absent or points to a non-cwd panel socket, it reads `KITTY_PID`'s environment to recover the original `KITTY_LISTEN_ON`; this covers quick-access-terminal children such as lazygit and nnn. As a final fallback it derives the same socket from the caller's current working directory. The Neovim autocmd owns the focus handoff after those requests display a buffer.
- Scripts that talk directly to Neovim sockets instead of going through `open_in_nvim`, such as `nvim/bin/nvim` and `term/bin/kitty-check-tasks-running`, use the same shared resolver from `term/bin/kitty-window-utils.sh`.
- `term/bin/kitty-open-in-editor` derives candidate Neovim server sockets from the target file's parent directories and sends the edit request directly with `open_in_nvim --cwd`. It does not enumerate Kitty remote-control sockets. Neovim's autocmd still owns the final focus step.
- Kitty's `kitty_mod+a>c` hint matches `@agent <id>` trailers and calls `open_in_nvim agent_conversation <id>`. That bridge invokes `CodexResumeById`, which shares the same selected-session resume helper as the `<leader>cl` picker after a session id has been selected, so agent-id hints and picker selections resume sessions through the same Overseer task creation logic. Session discovery is owned by `utilities/bin/codex-session-store`; Neovim and assistant commit tooling should call that script instead of duplicating `~/.codex/sessions` parsing. The picker sorts sessions by `updated_at`, derived from the session file mtime, so resumed chats move back to the top after Codex writes new activity.
- Lazygit consumes those subcommands via custom commands declared in `lazygit/dot-config/lazygit/config.yml`. See [lazygit.md](./lazygit.md) for the lazygit-specific bindings.
- Showing the lazygit panel is owned by the `kitty_mod+s` binding in `term/dot-config/kitty/kitty.conf`. Neovim has no keymap for it.
- Showing nnn panels is owned by `term/bin/kitty-nnn-quick-access`. `kitty_mod+r` opens the session-wide panel, and Neovim's `<leader>e` opens a separate Neovim-owned panel with the current buffer path.
- `term/bin/kitty-check-tasks-running` is the `kitty_mod+x` close helper. It queries the CWD-derived Neovim server directly with `nvim --server ... --remote-expr` to decide whether Overseer has running tasks marked `PREVENT_QUIT`; it should not depend on a Neovim user command or a sidecar state file.
