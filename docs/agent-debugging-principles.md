# Agent Debugging Principles

Prefer discovering existing runtime state before adding parameters, environment variables, caches, files, or one-off wiring.

- First inspect available channels: parent/supervisor environment, `/proc` metadata, tool APIs such as Kitty remote control, cwd/command line/window ids/user vars, and existing wrapper contracts.
- If several tools need the same value, centralize the resolver and have callers use it.
- If data seems missing, check whether it exists in another shape, such as parent pid, socket, window id, or cwd.
- Add new explicit state only after proving no stable existing source is available.
- Document reusable resolution rules near the owning workflow doc so future fixes do not add per-tool exceptions.

## Headless X Debugging

`utilities/bin/xscreen` drives a throwaway Xvfb display so GUI/terminal bugs (cursor visibility, rendering, input routing) can be reproduced, screenshotted, OCR'd, and compared without touching a real desktop.

- `xscreen start -D :98` starts Xvfb; `run` launches an app in the background, `shot` captures the screen, `ocr`/`blink`/`cursor` analyze it, `keys` injects input (prefers a kitty `--listen-on` socket, falls back to `xdotool`), and `stop` tears everything down.
- `xscreen stack --mode tmux --wrapper` reproduces the kitty → nvim → tmux → opencode chain and reports whether a blinking cursor exists (the reliable signal; static-block and OCR results are secondary). Run it with `--expect-cursor` to fail when the cursor is missing.
- In the agent sandbox the real `~/.local/kitty.app` and the nvim runtime are hidden; pass explicit `--kitty`/`--nvim` binaries (for example the copies under `/run/media/aaaa/dev4/arch-home-backup/`) and a self-contained nvim such as the nightly tarball when reproducing the stack here.

## Firejail Agent Orchestration

- Terminal agents launched through `fj-claude`, `fj-codex`, `fj-gemini`, and `fj-opencode` must expose the real Stow symlink targets needed by runtime helpers, especially `~/dotfiles/utilities` for `agent-tasks` and `~/dotfiles/for-my-eyes-only` for private helper symlinks that the user has explicitly allowed.
- The AI-agent wrapper always exposes `~/dotfiles` read-write regardless of the launched project, matching the access agents get when cwd is `~/dotfiles`, so agents keep workstation context from any project.
- The AI-agent profile does not blacklist `~/data/notes/foam`. `fj-ai-agent` controls exposure through whitelists: it always whitelists the current agent's own notes dir (`~/data/notes/foam/agents/<agent>`) read-write so the agent can persist transcripts from any project, and it whitelists the launch work root read-write on every run. Because Firejail mounts a tmpfs over `$HOME` (the whitelist top directory) and only bind-mounts whitelisted paths back in, a work root inside the foam tree exposes the notes whole while other launches see only the agent's own notes dir.
- Their default writable project root is the current Git root, falling back to the launch cwd only outside Git repositories; use `--root` when a narrower or different root is intentional.
- `agent-tasks` talks to the already-running Neovim host through `$AGENT_TASKS_NVIM` or `$NVIM`; the AI-agent wrapper forwards both so sub-agent orchestration does not need a separate discovery mechanism inside the sandbox.
- Agent tmux sessions use `tmux -L <nvim-server-name>` and place sockets below `/tmp/tmux-$uid`; because the dev-tool baseline uses `private-tmp`, the AI-agent wrapper exposes that socket directory read-write when it exists.
- Google Cloud Source Repository pushes may call `gcloud auth git-helper`; AI-agent sandboxes expose `~/.config/gcloud` read-write so the helper can read accounts and update Cloud SDK logs/state without opening all of `~/.config`.

## Sandbox Access Boundaries

Terminal agents always run inside the `fj-*-agent` Firejail sandbox, so some host paths and buses are simply not reachable. Assume the access granted by `playbooks/roles/20-dev-tools/templates/ai-agent-common.inc` (plus the generated `ai-agent-stow-targets.inc` mirror) is the full budget; do not ask to widen the sandbox for normal config work.

- `~/dotfiles` is exposed read-write from any project. `~/dotfiles/utilities` and `~/dotfiles/for-my-eyes-only` are `whitelist-ro`; `~/.ssh`, `~/.gnupg`, `~/data/secrets` are blacklisted. The current agent's own notes dir `~/data/notes/foam/agents/<agent>` is always whitelisted read-write; the rest of the private foam tree is hidden unless the launch work root is inside the foam tree (whitelisted read-write on every run).
- There is no session D-Bus (`dbus-user none`) and no way to reach the system scope bus, so `systemctl`/`busctl`/`journalctl` against either bus and `--machine=<user>@.host` fail. User-level verification that needs a live bus must be handed to the user.
- The sandbox uses a private `/dev`: real block nodes and `/dev/disk/by-*` are absent, so `lsblk <dev>`, `blkid <dev>`, and `udevadm info --name=<dev>` cannot inspect host disks. The host mount table remains readable through `mount` and `/proc/mounts`, and `/run/media` content stays visible.
- Consequence for storage work: take device UUIDs/labels from repo defaults such as `arch_filesystem_autolabels` and `arch_filesystem_automounts`, and mount state from `/proc/mounts`; never rely on live udev or device-node probes.
