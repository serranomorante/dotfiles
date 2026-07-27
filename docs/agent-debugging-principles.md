# Agent Debugging Principles

Prefer discovering existing runtime state before adding parameters, environment variables, caches, files, or one-off wiring.

- First inspect available channels: parent/supervisor environment, `/proc` metadata, tool APIs such as Kitty remote control, cwd/command line/window ids/user vars, and existing wrapper contracts.
- If several tools need the same value, centralize the resolver and have callers use it.
- If data seems missing, check whether it exists in another shape, such as parent pid, socket, window id, or cwd.
- Add new explicit state only after proving no stable existing source is available.
- Document reusable resolution rules near the owning workflow doc so future fixes do not add per-tool exceptions.

## Firejail Agent Orchestration

- Terminal agents launched through `fj-claude`, `fj-codex`, and `fj-gemini` must expose the real Stow symlink targets needed by runtime helpers, especially `~/dotfiles/utilities` for `agent-tasks` and `~/dotfiles/for-my-eyes-only` for private helper symlinks that the user has explicitly allowed.
- Their default writable project root is the current Git root, falling back to the launch cwd only outside Git repositories; use `--root` when a narrower or different root is intentional.
- `agent-tasks` talks to the already-running Neovim host through `$AGENT_TASKS_NVIM` or `$NVIM`; the AI-agent wrapper forwards both so sub-agent orchestration does not need a separate discovery mechanism inside the sandbox.
- Agent tmux sessions use `tmux -L <nvim-server-name>` and place sockets below `/tmp/tmux-$uid`; because the dev-tool baseline uses `private-tmp`, the AI-agent wrapper exposes that socket directory read-write when it exists.
- Google Cloud Source Repository pushes may call `gcloud auth git-helper`; AI-agent sandboxes expose `~/.config/gcloud` read-write so the helper can read accounts and update Cloud SDK logs/state without opening all of `~/.config`.
