# Change Workflow

This repository configures a real workstation. Treat changes as production
changes: keep them narrow, verify what you can locally, and avoid surprising
system actions.

## Before Editing

1. Check the working tree:

   ```sh
   git -C ~/dotfiles status --short
   ```

1. Identify unrelated dirty files and leave them alone.

1. Read the owning files before editing. For text search, prefer `rg`.

1. If a behavior is managed by Ansible, update the playbook/template/source file
   rather than only changing the generated destination under `/etc`, `~/.config`,
   or `~/bin`.

## Editing Rules

- Match the existing style of the file.
- Keep shell scripts POSIX `sh` unless the file already requires Bash.
- Keep comments useful and short. Add comments when they explain non-obvious
  behavior or latency-sensitive tradeoffs.
- Scripts should start with a brief header after the shebang, and after any
  generated-file marker. Use this structure by default:
  `Purpose:` one or two lines describing what the script does; `Usage:` only
  when invocation is not obvious; `Notes:` only for important side effects,
  assumptions, or external state.
- Avoid new dependencies unless the playbooks declare them.
- If a new runtime dependency is required, add it to the relevant Ansible task
  and do not install it manually unless asked.
- For Ansible templates, include an appropriate file-format comment containing
  `{{ ansible_managed }}` near the top unless the target format cannot carry
  comments.
- Do not rewrite unrelated sections for formatting.
- When you learn a durable project structure, convention, workflow, or
  operational rule that would help future work, update the relevant document in
  `docs/` as part of the same change. Keep those notes vendor-neutral and
  focused on repository practice rather than tool-specific memory.

## Validation

Use the smallest validation that matches the change.

Shell scripts:

```sh
sh -n path/to/script
```

Ansible syntax, when requested or appropriate:

```sh
cd ~/dotfiles/playbooks
ansible-playbook --syntax-check tools.yml -l localhost
```

Keyd templates:

```sh
cd ~/dotfiles/playbooks
ansible-playbook --syntax-check tools.yml -l localhost --tags 10-40
```

Do not reload keyd, restart user services, or run full playbooks unless the task
explicitly calls for applying the change to the active system.

## Commit Hygiene

After completing and validating an implementation, create a commit unless the
user explicitly asks to leave the change uncommitted or more work is still
planned in the same turn.

When committing:

1. Re-check status:

   ```sh
   git -C ~/dotfiles status --short
   ```

1. Stage exact paths only:

   ```sh
   git -C ~/dotfiles add path/one path/two
   ```

1. Confirm staged files:

   ```sh
   git -C ~/dotfiles diff --cached --name-only
   ```

1. Commit with a scoped message, for example:

   ```sh
   git -C ~/dotfiles commit -m "fix(keyd): release mouseless before swapfocus"
   ```

## Active System Application

Many source files are not active until the user deploys them:

- keyd config templates need Ansible or manual install to `/etc/keyd/default.conf`.
- systemd units need stowing/reload/restart depending on the change.
- scripts under stowed packages are usually active immediately for new
  invocations once linked into `~/bin`.
- scripts run by long-lived user services, such as `keyd-observer.service`, need
  the relevant `systemctl --user restart ...` before the running session uses
  the new script code.
- helper scripts that compile cached binaries may need a cache version bump when
  embedded source code changes.

When changing Ansible playbooks, include exactly one suggested
`ansible-playbook` command in the final response. Combine all relevant tags in a
single `--tags` value instead of listing multiple commands.

If active-system testing is needed, say which service or command would apply the
change before running it.
