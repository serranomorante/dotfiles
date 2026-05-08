# Project Instructions

`AGENTS.md` is the canonical, vendor-neutral context entrypoint for this
repository. Tool-specific files such as `CLAUDE.md` or `GEMINI.md` are generated
as symlinks to this file by Ansible and must not become separate sources of
truth.

When starting work, read these files from the repository root:

- `~/dotfiles/docs/project-context.md`
- `~/dotfiles/docs/repository-map.md`
- `~/dotfiles/docs/change-workflow.md`

If this file is being read through a symlink from a package directory such as
`~/dotfiles/playbooks` or `~/dotfiles/systemd`, still resolve the documentation
paths relative to `~/dotfiles`.

Operational expectations:

- Treat `~/dotfiles` as the source of truth for this workstation.
- Keep changes narrow and follow existing Ansible/Stow/script patterns.
- Do not touch `for-my-eyes-only` unless explicitly requested.
- Do not run Ansible, reload systemd, restart services, or apply active-system
  changes unless explicitly requested.
- Preserve unrelated dirty files.
- When a durable project structure, convention, workflow, or operational rule is
  learned, update the relevant file under `docs/` so future work has the same
  context.
