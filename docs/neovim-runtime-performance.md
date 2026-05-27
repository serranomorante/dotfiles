# Neovim Runtime Performance

Neovim runs Lua callbacks, timers, user commands, keymaps, and terminal
interaction on its main event loop. Code that is triggered from interactive
paths must keep that loop responsive, especially code used by Overseer
terminals, floating task windows, completion, folds, keymaps, and remote
commands.

## Main-Loop Rule

Do not put expensive filesystem scans, recursive directory walks, large file
reads, JSON parsing over many files, shell command waits, network calls, or
polling loops directly in Lua callbacks that run on the main Neovim thread.
`vim.defer_fn()` only delays execution; it does not make the delayed callback
run off-thread. A deferred callback that calls blocking APIs can still freeze
terminal input and redraw when it eventually runs.

Prefer these patterns:

- Use libuv async APIs (`vim.uv.fs_scandir`, async job callbacks, timers, pipes,
  and handles) when the work can naturally be expressed with nonblocking events.
- Use the `promise-async` plugin (`require("promise")` and `require("async")`)
  for multi-step async flows so call sites can stay readable with `await`.
- Use `vim.fn.jobstart()` or another background worker for CPU-heavy parsing,
  recursive scans, or work that standard Lua/libuv APIs would still perform
  synchronously on the main loop.
- Keep polling in a single background worker when possible. If polling must
  happen in Lua, each iteration should only check cheap in-memory state or a
  single nonblocking result.
- Treat `<leader>` mappings, terminal output subscribers, autocmds, and remote
  socket handlers as latency-sensitive entrypoints.

## Review Checklist

Before committing Neovim runtime code, check whether any interactive path does
one of these synchronously:

- Calls `vim.fn.system()` or waits for external commands.
- Recursively scans directories or reads many files.
- Parses large files or many JSON records.
- Uses `vim.defer_fn()` around heavy synchronous work and assumes that makes it
  safe.
- Polls by repeatedly doing filesystem or process discovery from Lua.

If any item applies, move the work behind a promise/async flow and a nonblocking
primitive, or document why the synchronous work is bounded and harmless.
