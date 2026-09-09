# Named Marks

Cross-tool named marks with custom labels: save a position under a letter, attach a free-form label, and jump back through a picker. tmux copy-mode marks and Neovim global marks share one label store so the label handling is implemented once and new systems can reuse it.

## Shared label store

- `utilities/bin/marks-common.sh` — POSIX `sh` library. Source it to get the `marks_*` helpers. It defines a scope-namespaced `key=value` file store and performs no side effects.
- `utilities/bin/marks-label` — thin CLI over the library for non-shell consumers (Neovim). Subcommands: `get|set|clear|list <scope> [key [value]]`.

Labels are stored per scope at `$XDG_STATE_HOME/dotfiles/marks/<scope>.labels`, where `<scope>` is a caller-defined namespace sanitized to `[A-Za-z0-9._-]`. A scope is the identity the host already uses to scope its positions:

- tmux copy marks: the tmux session name.
- Neovim global marks: the cwd key (`sha256(cwd)[1..8]`), matching the per-cwd shada scope.

Positions stay host-owned and use each host's native mechanism; only labels go through the shared store. `set` collapses whitespace and trims; `clear` removes a key (and the file once empty); `list` emits `key<TAB>value` lines.

## tmux

`term/bin/tmux-copy-mark` sources the library and stores labels/snippets under keys like `a-label` and `a-snippet` in the session scope. Position data is unchanged: tmux pane options persisted to `$XDG_STATE_HOME/dotfiles/tmux-copy-mark/state-<session-name>`.

## Neovim

`nvim/dot-config/nvim/lua/serranomorante/global_marks.lua` uses native Vim uppercase global marks (`mA`-`mZ`, persisted through the per-cwd shada) for positions and the shared store for labels (key `<letter>-label`).

Keymaps (in `remap.lua`):

- `<A-l>` save/reassign a mark with a label prompt.
- `<A-'>` jump to a labelled mark through the picker.
- `<A-d>` delete a mark and its label.

The module resolves `marks-label` via `MARK_LABEL_BIN`, then the repo path `~/dotfiles/utilities/bin/marks-label`, then `$PATH`.

## Adding a new system

Store positions with the host's native mechanism, then reuse `marks_meta_get`/`marks_meta_set`/`marks_meta_clear`/`marks_meta_list` (from shell) or the `marks-label` CLI (from other runtimes) with a scope that matches that host's position scoping. Do not reimplement label file handling.
