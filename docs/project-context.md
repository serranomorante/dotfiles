# Project Context

`~/dotfiles` declares one personal workstation through Ansible playbooks, GNU Stow packages, scripts, templates, patches, assets, and user services. Optimize for this existing workflow, not generic portability.

Read [repository-map.md](./repository-map.md) to find ownership and [change-workflow.md](./change-workflow.md) before editing. Use [agent-debugging-principles.md](./agent-debugging-principles.md) when diagnosing cross-process or runtime-state problems.

## Boundaries

- `AGENTS.md` is the only public assistant entrypoint. Compatibility filenames and package-local entrypoints are Ansible-generated symlinks.
- Add new assistant context filenames to `dotfiles_agent_context_symlink_names`; do not create separate sources of truth.
- `for-my-eyes-only` is an optional private package/submodule. Touch it only when explicitly requested; then read its private `docs/agent-context.md` if present.
- `~/data/notes/foam` is private. Do not inspect it unless explicitly permitted. In this repo, “foam” means that private PKM workspace; public tooling boundaries are documented in `docs/foam-notes.md`.

## System Model

- Main playbook: `playbooks/tools.yml`; testing dependencies: `playbooks/testing.yml`.
- Role order: `10-system-tools`, `20-dev-tools`, `30-lang-tools`, `40-PKM`, `50-cloud-tools`, then private roles when present.
- Dotfile stowing is owned by `playbooks/roles/10-system-tools/tasks/30-setup-dotfiles.*.yml`.
- Public Stow packages include `peripherals`, `nvim`, `term`, `audio`, `utilities`, `systemd`, `home`, `PKM`, `dunst`, `lazygit`, and `termux`.
- `dot-*` paths become hidden files through Stow; for example `dot-config/foo` maps to `~/.config/foo`.

## Preferences

- Keep paired modifier keys symmetric unless the task explicitly asks otherwise.
- Recommend established, currently healthy open-source projects when the recommendation affects meaningful setup time or risk.
- Treat changes here as production workstation changes: small scope, explicit ownership, local validation where practical, no surprising active-system actions.
