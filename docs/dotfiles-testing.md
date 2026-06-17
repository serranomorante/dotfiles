# Dotfiles Testing

Persistent tests live under `tests/` and are executed through the root `Makefile`. Use `make test` as the stable entrypoint, with filters such as `UNIT=nvim`, `FILE=tests/nvim/markdown_block_ids.sh`, or `NAME=markdown-block-ids-wikilink-file` for narrower runs.

Each declared test case is isolated. The runner creates a fresh temporary environment for every case, sets temporary XDG paths and `HOME`, and runs the case through Firejail by default. A test must not rely on mutable state left by another test. If a group of tests needs shared preparation, express that as setup/teardown in the owning framework or test file.

Test files declare required read-only host paths with `# dotfiles-test-readonly:` metadata. Keep these allowlists narrow: expose the exact binary, runtime directory, fixture root, or managed data path needed by that unit instead of exposing broad home-directory state.

The runner's core per-test contract is environment-based. For every `# dotfiles-test-case:` declaration, `tests/run` invokes the owning file once with `DOTFILES_TEST_CASE` set to that case name, `DOTFILES_TEST_ROOT` set to the absolute repository root, and `DOTFILES_TEST_TMP` set to that case's isolated writable temp directory. A shell test file should dispatch on `DOTFILES_TEST_CASE`; other frameworks can adapt the same contract by using a small shell wrapper that maps the selected case into the framework's native test selector.

`DOTFILES_TEST_CASE` is not user-facing configuration. It is the runner-to-test-file selector that lets one file contain related cases while still preserving individual execution, filtering, reporting, and isolation. Use `make test NAME=<case>` or `tests/run --name <case>` to select a case from outside; do not ask users to set `DOTFILES_TEST_CASE` manually except when debugging the test file itself.

The other stable runner contracts are:

- Metadata is read from leading-style comments named `# dotfiles-test-unit:`, `# dotfiles-test-tags:`, `# dotfiles-test-firejail:`, `# dotfiles-test-readonly:`, and `# dotfiles-test-case:`.
- `# dotfiles-test-unit:` controls unit filtering; if it is omitted, the unit is inferred from the first path segment under `tests/`.
- `# dotfiles-test-tags:` controls `--tags` filtering; requested tags are comma-separated and all requested tags must be present.
- `# dotfiles-test-firejail: disabled` runs the file outside Firejail while still using the runner's temporary `HOME`, XDG directories, and `TMPDIR`; reserve it for integration tests that are blocked by Firejail itself, such as GUI Wine processes that trip the sandbox's syscall restrictions.
- `# dotfiles-test-readonly:` must be an absolute existing host path; each declaration becomes a read-only Firejail allowlist entry.
- `DOTFILES_TEST_ROOT` is the absolute dotfiles repository root, exposed read-only when Firejail is enabled and used as cwd.
- `DOTFILES_TEST_TMP` is the writable temp root for the current individual case; passing and skipped cases remove it, failing cases keep it and print the path.
- `test-output.log` under `DOTFILES_TEST_TMP` captures stdout and stderr for each individual case. The runner prints this log on failure so `make` output includes the underlying assertion or tool error instead of only the final Make error.
- `DOTFILES_TEST_NO_FIREJAIL=1` disables Firejail only for debugging the harness.
- `DOTFILES_TEST_ALLOW_NESTED_FIREJAIL=1` bypasses the nested-Firejail guard only for explicit experiments; do not depend on it without first investigating nested Firejail behavior.
- Exit code `0` means pass, exit code `77` means skip, and any other non-zero exit code means fail.
- Discovery currently targets shell files named `*.sh` one directory below `tests/`; deeper or non-shell test frameworks should be wrapped by a shell file that exposes the same metadata contract.

Neovim has two useful test layers. Isolated behavior tests should use `nvim --headless -u NONE` and add only the repo runtimepath they need. Integrated Neovim tests should load the active configuration through temporary XDG directories and read-only host allowlists: symlink `/home/aaaa/.config/nvim` into the temporary `XDG_CONFIG_HOME`, symlink plugin data such as `/home/aaaa/.local/share/nvim/site` into the temporary `XDG_DATA_HOME`, and keep state/cache writes inside `DOTFILES_TEST_TMP`. This catches plugin, parser, LSP, ftplugin, keymap, and runtimepath conflicts without writing to the host configuration.

Neovim regressions that depend on real Terminal-mode state or TUI input delivery, such as chained terminal-backed pickers, should include a pseudo-TTY test with `script(1)` or an equivalent PTY driver. Headless tests may still guard internal contracts, but they are not sufficient when the failure is whether a visible terminal buffer actually receives typed keys.

Fast Neovim local-state tests should prefer headless checks for concrete option/path behavior, such as cwd-keyed `shadafile`, cwd-keyed `undodir`, broad-cwd persistence disablement, and buffer-local persistent undo suppression for secret-looking paths. These tests should not launch the full UI or require real workstation cache/state directories.

Tests should be hermetic by default and should prefer behavior checks over load-only checks for features where regressions matter. Load checks are still useful as cheap smoke tests, especially for Neovim modules, shell syntax, systemd unit verification, and formatter/linter checks.

Wine GUI wrapper tests should use a temporary `WINEPREFIX` under `DOTFILES_TEST_TMP` and `xvfb-run` for headless windows. Prefer lightweight built-in Wine programs such as `notepad` plus explicit registry or window-tree assertions instead of launching workstation applications such as REAPER or external Wine audio host. Wine may need `# dotfiles-test-firejail: disabled` because it can abort under the runner's Firejail sandbox before the wrapper behavior is exercised.

Temporary debugging output added while developing a test must be removed before the change is considered finished. Durable failure information should flow through assertions, stdout, or stderr so the runner captures it in `test-output.log`; do not leave ad hoc debug log files or diagnostic traces in test fixtures unless that log is part of the test contract and documented.

Firejail is the default isolation boundary for test execution. The runner does not intentionally depend on nested Firejail; any design that requires `firejail` inside `firejail` needs a focused investigation first, including whether the nesting is supported and whether it preserves the desired guarantees.

Tests whose subject is Firejail orchestration itself, such as wrapper behavior around `firejail --join-or-start`, inherited sandbox validation, or named sandbox sharing, should use `# dotfiles-test-firejail: disabled` and invoke the real `firejail` binary inside the test fixture. Keep those fixtures fast by using fake payload executables instead of launching workstation applications, and assert the real Firejail boundary through observable state such as `firejail --list`, `/run/firejail/profile`, and wrapper logs.

The runner invokes Firejail with deterministic shutdown and deterministic exit-code modes. This is important for integration tests that start child processes such as LSP servers: Firejail's default behavior is to keep the sandbox alive while processes remain and to use the final child's exit status, which can make test results nondeterministic. Deterministic shutdown makes the sandbox close when the test process exits, and deterministic exit-code makes Firejail report the test process status.

Test dependencies are managed by `playbooks/testing.yml` and the dedicated `60-testing-tools` role. Do not add undocumented manual dependencies for persistent tests; declare the package or managed tool in that role, or make the test skip/fail clearly when an optional capability is unavailable.
