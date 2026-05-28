# Dotfiles Testing

Persistent tests live under `tests/` and are executed through the root `Makefile`. Use `make test` as the stable entrypoint, with filters such as `UNIT=nvim`, `FILE=tests/nvim/markdown_block_ids.sh`, or `NAME=markdown-block-ids-wikilink-file` for narrower runs.

Each declared test case is isolated. The runner creates a fresh temporary environment for every case, sets temporary XDG paths and `HOME`, and runs the case through Firejail by default. A test must not rely on mutable state left by another test. If a group of tests needs shared preparation, express that as setup/teardown in the owning framework or test file.

Test files declare required read-only host paths with `# dotfiles-test-readonly:` metadata. Keep these allowlists narrow: expose the exact binary, runtime directory, fixture root, or managed data path needed by that unit instead of exposing broad home-directory state.

The runner's core per-test contract is environment-based. For every `# dotfiles-test-case:` declaration, `tests/run` invokes the owning file once with `DOTFILES_TEST_CASE` set to that case name, `DOTFILES_TEST_ROOT` set to the absolute repository root, and `DOTFILES_TEST_TMP` set to that case's isolated writable temp directory. A shell test file should dispatch on `DOTFILES_TEST_CASE`; other frameworks can adapt the same contract by using a small shell wrapper that maps the selected case into the framework's native test selector.

`DOTFILES_TEST_CASE` is not user-facing configuration. It is the runner-to-test-file selector that lets one file contain related cases while still preserving individual execution, filtering, reporting, and isolation. Use `make test NAME=<case>` or `tests/run --name <case>` to select a case from outside; do not ask users to set `DOTFILES_TEST_CASE` manually except when debugging the test file itself.

The other stable runner contracts are:

- Metadata is read from leading-style comments named `# dotfiles-test-unit:`, `# dotfiles-test-tags:`, `# dotfiles-test-readonly:`, and `# dotfiles-test-case:`.
- `# dotfiles-test-unit:` controls unit filtering; if it is omitted, the unit is inferred from the first path segment under `tests/`.
- `# dotfiles-test-tags:` controls `--tags` filtering; requested tags are comma-separated and all requested tags must be present.
- `# dotfiles-test-readonly:` must be an absolute existing host path; each declaration becomes a read-only Firejail allowlist entry.
- `DOTFILES_TEST_ROOT` is the absolute dotfiles repository root, exposed read-only in Firejail and used as cwd.
- `DOTFILES_TEST_TMP` is the writable temp root for the current individual case; passing and skipped cases remove it, failing cases keep it and print the path.
- `DOTFILES_TEST_NO_FIREJAIL=1` disables Firejail only for debugging the harness.
- `DOTFILES_TEST_ALLOW_NESTED_FIREJAIL=1` bypasses the nested-Firejail guard only for explicit experiments; do not depend on it without first investigating nested Firejail behavior.
- Exit code `0` means pass, exit code `77` means skip, and any other non-zero exit code means fail.
- Discovery currently targets shell files named `*.sh` one directory below `tests/`; deeper or non-shell test frameworks should be wrapped by a shell file that exposes the same metadata contract.

Tests should be hermetic by default and should prefer behavior checks over load-only checks for features where regressions matter. Load checks are still useful as cheap smoke tests, especially for Neovim modules, shell syntax, systemd unit verification, and formatter/linter checks.

Firejail is the default isolation boundary for test execution. The runner does not intentionally depend on nested Firejail; any design that requires `firejail` inside `firejail` needs a focused investigation first, including whether the nesting is supported and whether it preserves the desired guarantees.

Test dependencies are managed by `playbooks/testing.yml` and the dedicated `60-testing-tools` role. Do not add undocumented manual dependencies for persistent tests; declare the package or managed tool in that role, or make the test skip/fail clearly when an optional capability is unavailable.
