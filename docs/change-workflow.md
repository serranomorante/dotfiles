# Change Workflow

This repository configures a real workstation. Treat changes as production changes: keep them narrow, verify what you can locally, and avoid surprising system actions.

## User-Facing Command Formatting

This is a user-wide assistant convention, not only a dotfiles convention. In any repository, whenever an assistant suggests a shell command for the user to run, the command must be shown with escaped fenced shell delimiters so the literal opening and closing fence lines remain visible in terminal buffers:

    \`\`\`sh
    command ...
    \`\`\`

This rule applies to Ansible, Stow, systemctl, validation, follow-up commands, and every other suggested shell command. Do not use normal Markdown code fences for user-facing commands.

## Before Editing

1. Check the working tree:

   ```sh
   git -C ~/dotfiles status --short
   ```

1. Identify unrelated dirty files and leave them alone.

1. Read the owning files before editing. For text search, prefer `rg`.

1. If a behavior is managed by Ansible, update the playbook/template/source file rather than only changing the generated destination under `/etc`, `~/.config`, or `~/bin`.

1. If a file is delivered by a Stow package, add or update the package source and run the repository Stow wrapper instead of creating symlinks directly in the target tree. Direct `ln -s` fixes can later conflict with Stow or hide package conflicts. If Stow fails, report the exact conflict and leave unrelated target files untouched rather than bypassing Stow manually.

## Editing Rules

- Match the existing style of the file.
- When writing or editing Markdown prose, keep each paragraph or list item on a single physical line. Do not insert manual hard wraps inside the same paragraph just to keep lines under a column limit. Use line breaks only when Markdown syntax requires them or when the content is intentionally multi-line, such as fenced code blocks, tables, quoted excerpts, nested lists, or other structured blocks.
- Keep shell scripts POSIX `sh` unless the file already requires Bash.
- Executable scripts intended to be run from `~/bin` or another `PATH` directory should not include a language extension such as `.sh` in the command name. Keep extensions only for sourced libraries, generated snippets, or legacy files that are not being renamed in the current change.
- Keep comments useful and short. Add comments when they explain non-obvious behavior or latency-sensitive tradeoffs.
- Avoid fixed sleeps, arbitrary delays, and timing-based retries for readiness unless there is no practical observable signal. Prefer events, process output, sockets, files, exit states, API responses, or other explicit state. When a timing fallback is truly unavoidable, keep it bounded and document why no better signal is available.
- Scripts should start with a brief header after the shebang, and after any generated-file marker. Use this structure by default: `Purpose:` one or two lines describing what the script does; `Usage:` only when invocation is not obvious; `Notes:` only for important side effects, assumptions, or external state.
- Script `--help` output is part of the script contract. When adding, removing, or renaming supported command-line options or environment variables, update the script's help text in the same change so discoverable documentation stays aligned with runtime behavior.
- Private one-command shortcuts should be exposed through the `sx` dispatcher instead of adding many top-level commands to `~/bin`. Put the shortcut implementation under the Stow-managed private package, include a `# sx-description: ...` header in each shortcut script, and keep `sx --list`, `sx --list-descriptions`, `sx --help`, and shell completion aligned. When ble.sh completion is available, completion entries should show the same short descriptions alongside each shortcut name; plain Bash completion should remain a working fallback.
- Avoid new dependencies unless the playbooks declare them.
- If a new runtime dependency is required, add it to the relevant Ansible task and do not install it manually unless asked.
- Treat new tools, apps, model downloaders, install scripts, and language package-manager flows as supply-chain-risky by default. Use pacman-managed packages when they satisfy the need because they keep ownership, upgrades, and removal reproducible, but do not treat them as immune to compromise. For AUR packages, upstream binary downloads, `curl | sh` style installers, Python, Node, npm, pnpm, Cargo, Go, and similar ecosystems, use the repository Firejail wrappers for installation and runtime execution whenever the task can be expressed that way. In Ansible, use `ansible-firejail-pip`, `ansible-firejail-npm`, or `ansible-firejail-pnpm` when possible. For runtime Python/Node tooling, prefer `fj-py` or `fj-node` with the narrowest viable network mode. If sandboxing is not practical, document the reason in the owning workflow doc or task comment. See [firejail-dev-tools.md](./firejail-dev-tools.md).
- For Ansible templates, include an appropriate file-format comment containing `{{ ansible_managed }}` near the top unless the target format cannot carry comments.
- Do not rewrite unrelated sections for formatting.
- When you learn a durable project structure, convention, workflow, or operational rule that would help future work, update the relevant document in `docs/` as part of the same change. Keep those notes vendor-neutral and focused on repository practice rather than tool-specific memory.
- After reaching a working solution in an interactive session, actively check whether the change revealed a new convention, operational rule, or maintenance expectation that belongs in `docs/`. Documentation updates should include new guidance when useful, not only edits to existing text.
- If a fix requires a manual operational step that is part of maintaining this workstation, prefer encoding that step in the owning Ansible task or handler so future runs can reproduce it. Do this especially when the step is not obvious to run manually, such as rebuilding generated caches, refreshing helper binaries, or restarting only the services affected by a changed artifact.
- For one-time migrations that remove an implementation pattern, clean up any stale files directly as part of the change when appropriate. Do not add a permanent Ansible task just to remove artifacts that the new implementation can no longer regenerate.
- When adding scripts that compile and cache embedded helpers or other generated runtime artifacts, include the compile/cache refresh step in the owning Ansible task. The script may still compile on demand for normal use, but the playbook should precompile or refresh the cache so applying dotfiles does not require a separate manual compilation step. If a refreshed artifact is used by a long-running service, have the Ansible task notify a restart handler only when the artifact actually changed.

## Validation

Use the smallest validation that matches the change.

Before validating behavior through the active `$HOME` configuration, check whether the change added new files under a Stow package. Existing symlinked files update in place, but new files do not exist under `$HOME` until the package is stowed. Run `~/bin/dotfiles-stow <package>` first, or explicitly say that the validation is using the repository path directly rather than the active configuration. This is especially easy to miss for new Neovim files under `ftdetect/`, `after/ftplugin/`, `plugin/`, or `lua/`, because edited existing files may be active while newly added companion files are not.

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

Do not reload keyd, restart user services, or run full playbooks unless the task explicitly calls for applying the change to the active system.

## Commit Hygiene

After completing and validating an implementation, create a commit unless the user explicitly asks to leave the change uncommitted or more work is still planned in the same turn.

Commit subjects use `<type>(<scope>): <imperative summary>`, for example `fix(keyd): release mouseless before swapfocus`. Prefer `fix`, `feat`, `docs`, `refactor`, `chore`, or `test`; keep the scope concrete and local to the changed area.

Commit bodies should explain the context behind the change, not merely restate the implementation that is already visible in the diff. Describe the problem or friction that led to the work, what outcome the change was meant to achieve, and the intent behind the chosen solution. Include operational impact when relevant. For very small self-explanatory changes, a subject-only commit is still fine.

When a commit is generated from an assistant conversation, include `@agent <conversation id>` in the commit body on its own physical line. Resolve Codex ids with `utilities/bin/codex-session-store current-id --cwd "$PWD"` or the active `codex-session-store` on `PATH`; this is the same session parser used by Neovim's Codex Overseer integration. Placeholder values such as `unknown`, `unavailable`, `none`, or `n/a` are never acceptable. If the id cannot be resolved, stop before committing instead of inventing a value. Keep the identifier line provider-neutral; do not name the assistant product or vendor.

When passing a multi-paragraph commit message non-interactively, use separate `git commit -m` arguments for the subject, body paragraphs, and `@agent` trailer. Do not embed escaped newline text such as `\n\n@agent ...` inside a quoted `-m` argument; Git records that literally instead of turning it into separate lines.

The repository commit-message guard lives at `utilities/git-hooks/commit-msg`. Keep `core.hooksPath` pointed at `utilities/git-hooks` for this repository. The hook validates `@agent` only when the trailer is present, so manual commits without an assistant conversation id remain valid; when `@agent` is present, placeholder values are rejected before they enter history.

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

1. Commit with a scoped message, using a separate `-m` for the assistant trailer when present:

   ```sh
   git -C ~/dotfiles commit -m "fix(keyd): release mouseless before swapfocus" -m "Explain why the change is needed and what behavior it preserves." -m "@agent <conversation id>"
   ```

Private submodule commits need two layers of history:

- Commit the actual private change inside `~/dotfiles/for-my-eyes-only` first.
- Then commit the updated `for-my-eyes-only` gitlink in `~/dotfiles` when the public repository should pin that private submodule revision.
- Keep detailed subjects, filenames, service names, feature names, bug details, and command output in the private submodule history only. The public parent commit should disclose only that the private submodule pointer changed.
- Use neutral parent-repo messages such as `chore(private): update private submodule pointer`, `chore(private): advance private package`, or `chore(submodule): update private package pointer`.
- If public files changed for the same work, prefer a separate public commit whose message describes only the public behavior. Do not copy the private submodule commit subject into the parent repository commit message or body.

## Active System Application

Many source files are not active until the user deploys them:

- Do not apply durable configuration by copying files directly into active system paths, creating ad hoc symlinks, reloading services, or restarting units. Encode the change in the owning Stow package or Ansible task, then use `~/bin/dotfiles-stow <package>` or the relevant Ansible tag to apply it.
- keyd config templates need Ansible to install `/etc/keyd/default.conf`.
- systemd units need stowing and then the relevant Ansible task or handler to reload/restart/enable them when active application is requested.
- scripts under stowed packages are usually active immediately for new invocations once linked into `~/bin`.
- new files under stowed packages must be stowed before the active system can see them. Existing symlinked files update immediately when edited, but newly created files need `~/bin/dotfiles-stow <package>` or an Ansible dotfile setup run. Mention this in the final response whenever adding new files under packages such as `nvim/`, `term/`, `peripherals/`, or `utilities/`.
- scripts run by long-lived user services, such as `keyd-observer.service`, need the relevant `systemctl --user restart ...` before the running session uses the new script code.
- helper scripts that compile cached binaries may need a cache version bump when embedded source code changes.

When changing Ansible playbooks, include exactly one suggested `ansible-playbook` command in the final response. Combine all relevant tags in a single `--tags` value instead of listing multiple commands. For active application commands, include `-K` so tasks that use `become` can prompt for the sudo password instead of failing mid-run. Format the command according to the user-facing command formatting rule above.

Append logging to suggested `ansible-playbook` commands so the resulting output can be inspected after the user runs the command. The Neovim Overseer `run-ansible-playbook` task follows the same convention.

```sh
2>&1 | tee /tmp/ansible-<scope>.log
```

`playbooks/ansible.cfg` sets `force_color = True`, so Ansible output keeps ANSI color while being piped through `tee`. The saved log can be read with `less -R /tmp/ansible-<scope>.log` when color escapes should be rendered.

Choose a stable, readable `/tmp` filename based on the command scope. Prefer the primary tag when there is one, such as `/tmp/ansible-10-30.log`; for combined tags, join them with underscores, such as `/tmp/ansible-10-20_20-90.log`; for a full playbook run without tags or the picker scope `all`, use `/tmp/ansible-tools.log`. Derive the scope from the requested Ansible tags, not from UI labels: strip picker descriptions such as `: Setup foo (...)` or `[Full editor setup]`, keep role tags as written, and join multiple tags in selection order with `_`.

Logs launched from Neovim include a short machine-readable header before the Ansible output:

```text
ansible-log-version: 1
cwd: /home/aaaa/dotfiles/playbooks
command: ansible-playbook ...
log_path: /tmp/ansible-<scope>.log
started_at_utc: <timestamp>
```

When reading a large log afterward, inspect it selectively with `tail`, `rg`, and narrow `sed -n` excerpts around matching line numbers instead of loading the whole file.

Before adding bootstrap, service-management, package-manager, or shared tooling setup to an Ansible task, search the existing playbooks for the same behavior and reuse the existing owner when one exists. If the requested task depends on that owner, leave the prerequisite there and include its tag in the single suggested `ansible-playbook` command instead of duplicating the setup in the new task.

If the requested playbook scope includes AUR tasks, such as tasks using `kewlfft.aur.aur`, make sure the AUR setup task runs first by including the `10-20` tag before the requested tag in that single command. This prepares `aur_builder`, `yay`, and the repo-local AUR collection from `playbooks/roles/10-system-tools/tasks/20-setup-aur.archlinux.yml`. For example, use `--tags 10-20,20-90` when applying a `20-90` task file that installs AUR packages.

Before editing any file under `~/dotfiles`, confirm whether the file is tracked by the relevant Git repository. Use the repo that owns the path, including submodules, and check `git ls-files -- <path>` first. When the file is not listed, also check `git check-ignore -v -- <path>`. If the file is ignored or untracked, assume it is generated, downloaded, cached, or otherwise outside source control until you identify the owning template, setup task, generator, or upstream checkout. Durable fixes should usually change that tracked source instead of relying on a direct edit to an ignored file that can be replaced later.

If active-system testing is needed, say which service or command would apply the change before running it.

## Arch System Upgrades

Do not run full-system upgrades from Ansible. Avoid `community.general.pacman` with `upgrade: true` and command tasks equivalent to `pacman -Syu` or `pacman -Su`. System upgrades should be an explicit operator action outside these workstation configuration playbooks so long-running playbook runs do not mix old in-memory Python or Ansible code with upgraded files on disk.
