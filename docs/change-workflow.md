# Change Workflow

This repo configures a real workstation. Keep edits narrow, preserve unrelated work, validate proportionally, and avoid active-system side effects unless requested.

## User-Facing Commands

When suggesting shell commands to the user, show escaped Markdown fences so literal fence lines remain visible:

    \`\`\`sh
    command ...
    \`\`\`

Use this for Ansible, Stow, systemctl, validation, and follow-up commands.

## Before Editing

1. Run `git -C ~/dotfiles status --short`; note unrelated dirty files and leave them alone.
2. For each target, verify ownership with `git -C <owning-repo> ls-files -- <path>`; if absent, check `git check-ignore -v -- <path>` and find the tracked source/generator before editing.
3. Read owning files first; use `rg` for search.
4. If managed by Ansible or Stow, edit the tracked playbook/template/package source, not generated destinations under `/etc`, `~/.config`, `~/bin`, etc.

## Editing Rules

- Match local style; do not reformat unrelated sections.
- Repository-authored prose, comments, labels, generated Markdown, and user-facing strings are English unless the literal subject requires another language.
- Markdown prose uses one physical line per paragraph/list item; no manual hard wraps.
- Keep shell scripts POSIX `sh` unless already Bash.
- PATH executables should normally have no `.sh` extension.
- Scripts start with a short `Purpose:` header; add `Usage:`/`Notes:` only when useful. Keep `--help` aligned with supported options/env vars.
- Keep comments short and explain non-obvious behavior or tradeoffs.
- Avoid arbitrary sleeps; prefer observable readiness signals. If timing fallback is necessary, bound and explain it.
- Avoid new dependencies. If required, declare them in the relevant playbook; do not install manually unless asked.
- Treat new tools/installers/package registries as supply-chain risk. Prefer reproducible package ownership and repository Firejail wrappers (`ansible-firejail-*`, `fj-py`, `fj-node`) when practical; document exceptions.
- Prefer updating all repository-owned callers over adding compatibility shims, unless an external consumer or explicit migration window exists.
- Encode durable maintenance steps in Ansible/handlers when possible. Ask before direct one-time active-system cleanup.
- When applying workstation Ansible from an agent session, limit the inventory to localhost with `-l localhost` unless the user explicitly asks to target other hosts.
- Local Go helpers should be built by Ansible into final command paths; avoid self-compiling wrappers unless they provide real runtime behavior.
- For patched upstream checkouts, gate clone/patch/build behind versioned central markers and bump marker contracts when local patch behavior changes.
- If a commit hook reports that Stow or Ansible must apply a new tracked file first, stop and give the user the exact declarative command to run; do not bypass hooks with `--no-verify`.
- Add durable conventions/workflows to focused docs when they will help future work, but keep startup context compact.

## Validation

- Use the smallest relevant check: examples include `sh -n path`, targeted unit tests, or `ansible-playbook --syntax-check`.
- Before validating through active `$HOME`, remember that new Stow-package files are inactive until stowed; say when validation used repo paths directly. Agent sessions run in a sandbox and cannot write to active `$HOME`, so when Stow is required, give the user the exact `dotfiles-stow` command instead of running it.
- Do not reload keyd, restart services, run full playbooks, or apply config unless explicitly requested.

## Commits

- Commit after implementation/validation unless the user asks not to, more work is planned, or the agent conversation id cannot be resolved.
- Always attempt the commit before finishing implementation work; if blocked by required user-side Stow/Ansible application, leave the index ready when appropriate and report the unblock command.
- Re-check status, stage exact paths only, and verify staged filenames.
- Subject format: `<type>(<scope>): <imperative summary>`; use concrete scopes and types such as `fix`, `feat`, `docs`, `refactor`, `chore`, `test`.
- Commit bodies explain context/intent/operational impact. For assistant-generated commits include `@agent <conversation id>` as its own line; never use placeholders. Resolve with `utilities/bin/agent-session-store ... current-id --cwd "$PWD"`.
- Private submodule work is committed first inside `for-my-eyes-only`, then the parent gitlink is committed separately with a neutral parent message.

## Active System Application

- Durable changes are applied through Stow or Ansible, not ad hoc copies/symlinks/restarts.
- keyd templates require Ansible to install `/etc/keyd/default.conf`; systemd units require stowing plus the relevant task/handler; long-lived services need restart to pick up script changes.
- When changing Ansible playbooks and suggesting application, provide a single-line command using `cd ~/dotfiles/playbooks && ansible-playbook tools.yml --tags <tag>`, include `-K` for become paths, and append `2>&1 | tee /tmp/ansible-<scope>.log`. Offer tags, not roles.
- If applying a scope that installs local AUR packages, include tag `10-20` before the requested tag so `[aur-local]` is prepared.
- Inspect large Ansible logs with `tail`, `rg`, and narrow `sed -n` excerpts, not full-file dumps.
