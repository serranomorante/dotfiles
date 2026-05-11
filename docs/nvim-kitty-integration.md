# Neovim And Kitty Window Integration

The Neovim/Kitty integration is scoped to the current Kitty UI window, not to
global tab positions. Each Kitty UI window has its own Neovim server socket,
and Neovim owns the Kitty focus handoff when a remote client opens or displays
a buffer in that server.

## Per-Window Neovim Server Socket

`term/bin/kitty` starts each Kitty UI window with a fresh
`NVIM_KITTY_LISTEN_ADDRESS` pointing at a unique socket path under
`$XDG_RUNTIME_DIR`.

The `nvim/bin/nvim` wrapper uses that socket to either reuse an existing
Neovim server or start a new listening server in the same Kitty window. It
stays out of the way for explicit client-server invocations
(`--server`, `--listen`, `--remote*`, `--headless`).

## Kitty Window Matching

While an interactive Neovim process is alive in a Kitty window, Kitty exposes
that process through the window cmdline / foreground-process data. The focus
helpers use that process data as the app identity signal.

`lazygit` participates the same way: it is launched normally from
`term/dot-config/kitty/default.kitty-session`, and helpers match
`cmdline:lazygit`.

## Remote Edit Focus Handoff

`nvim/dot-config/nvim/lua/serranomorante/remote_kitty_focus.lua` owns this
stateful handoff and is loaded from `serranomorante/init.lua`. It watches
`ChanOpen` for remote RPC clients on the per-window server socket. When a later
`BufEnter` or `BufWinEnter` follows shortly after that remote connection,
Neovim checks whether its own `$KITTY_WINDOW_ID` is already focused. If not, it
runs `kitten @ focus-window --match id:$KITTY_WINDOW_ID`.
That check must confirm the parent tab is active, not only that the window has
`is_focused=true`; Kitty can report active windows from inactive tabs that way
inside the focused OS window state.

The follow-up buffer/window event is intentional: background RPC commands that
only evaluate expressions or update state, such as color-mode broadcasts, should
not steal focus. Remote edits from `nvr`, native `nvim --server --remote`, and
`--remote-send` commands that open a buffer do trigger the handoff.

## Helpers

Shared, generic kitty window helpers live in
`term/bin/kitty-window-utils.sh` (sourced library, POSIX sh):

- `kitty_focus_match QUERY` — wraps `kitten @ focus-window --match`.
- `kitty_focus_window_id ID` — focus by numeric Kitty window id.
- `kitty_focused_os_windows_json` — emit the focused-OS-window subset of
  `kitten @ ls`.
- `kitty_target_window_id PROCESS_NAME` — search across the focused OS
  window's tabs by cmdline / foreground processes. On ties, the more recently
  focused window wins.

App-specific focus helpers live in the owning script. For the Neovim/lazygit
handoff that is `nvim/bin/open_in_nvim.sh`, which sources
`kitty-window-utils.sh` and defines:

- `kitty_focus_lazygit` — tries `cmdline:lazygit`, then
  `kitty_target_window_id lazygit`.

A cache is intentionally avoided in any of these helpers because the focused
Kitty window state is small, cheap to query, and easy to make stale.

## Consumers

- `nvim/bin/open_in_nvim.sh` exposes `focus_lazygit` and sends remote edit
  requests to the per-window Neovim server. The Neovim autocmd owns the focus
  handoff after those requests display a buffer.
- `term/bin/kitty-open-in-editor` finds a Kitty window by cwd and sends the
  edit request into that window. It also relies on the Neovim autocmd for the
  final focus step.
- Lazygit consumes those subcommands via custom commands declared in
  `lazygit/dot-config/lazygit/config.yml`. See [lazygit.md](./lazygit.md) for
  the lazygit-specific bindings.
- Neovim's `<leader>w` mapping in
  `nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/overseer.lua` shells
  out to `open_in_nvim.sh focus_lazygit`.
