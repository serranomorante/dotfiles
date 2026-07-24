# Project Instructions

`AGENTS.md` is the canonical assistant entrypoint for `~/dotfiles`; `CLAUDE.md`, `GEMINI.md`, and package-local entrypoints are generated symlinks and must not diverge.

On start, resolve paths relative to `~/dotfiles` and read:

- `docs/project-context.md`
- `docs/repository-map.md`
- `docs/change-workflow.md`

Core rules:

- Treat `~/dotfiles` as the source of truth for this workstation.
- Keep changes narrow and preserve unrelated dirty files.
- Do not inspect or modify `for-my-eyes-only` or private Foam notes unless explicitly requested.
- Do not run Ansible, Stow active deployment, reload systemd, restart services, or otherwise change the active system unless explicitly requested.
- Follow existing Ansible/Stow/script ownership instead of editing generated destinations.
- Markdown prose: one physical line per paragraph or list item; no manual hard wraps.
- If a durable convention or workflow is learned, update the relevant `docs/` file.
