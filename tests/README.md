# Dotfiles Tests

`make test` is the stable entrypoint for persistent dotfiles tests. The runner discovers executable shell test files under `tests/<unit>/`, treats each declared `# dotfiles-test-case:` line as an individual test, and executes each test case in its own temporary environment.

Each individual test must be isolated. A test that changes state must not affect the next test. Shared setup and cleanup for a group of related tests belong in explicit setup/teardown logic in the owning test file or framework, not in accidental runner state.

By default tests run through Firejail with a temporary `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, and `TMPDIR`. The repository is exposed read-only and the test temp directory is writable. `DOTFILES_TEST_NO_FIREJAIL=1` exists only for debugging the harness itself.

The runner refuses to intentionally run nested Firejail unless `DOTFILES_TEST_ALLOW_NESTED_FIREJAIL=1` is set for an explicit experiment. Before depending on nested Firejail for real tests, investigate whether it is possible and whether it preserves the expected isolation guarantees.

Examples:

```sh
make test
make test UNIT=nvim
make test FILE=tests/nvim/markdown_block_ids.sh
make test NAME=markdown-block-ids-wikilink-file
make test-list UNIT=nvim
```

Test files can declare metadata with comments near the top:

```sh
# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless firejail
# dotfiles-test-readonly: /absolute/path/needed/inside/firejail
# dotfiles-test-case: feature-loads
# dotfiles-test-case: feature-behavior
```

## Runner Contract

For each `# dotfiles-test-case:` declaration, the runner invokes the same test file once and sets `DOTFILES_TEST_CASE` to the selected case name. Shell test files should dispatch on that variable, usually with a `case` statement, so every declared case can be listed and run independently while sharing helper functions in the same file.

The runner also sets `DOTFILES_TEST_ROOT` to the absolute repository root and `DOTFILES_TEST_TMP` to the writable temporary root for the current individual test case. Use `DOTFILES_TEST_TMP` for all fixtures and generated files; do not write to the real home directory or depend on state created by another test case.

These contracts are intentionally visible and stable:

- `# dotfiles-test-unit:` declares the logical unit. When omitted, the first directory under `tests/` is used as the unit.
- `# dotfiles-test-tags:` declares space-separated or comma-separated tags used by `--tags`; every requested tag must be present.
- `# dotfiles-test-readonly:` declares one absolute host path to expose read-only inside Firejail. Repeat it for multiple paths. Paths must exist.
- `# dotfiles-test-case:` declares one stable individual test name. Repeat it for multiple cases in one file.
- `DOTFILES_TEST_CASE` is the selected case for the current invocation. It is set by the runner, not by normal users.
- `DOTFILES_TEST_ROOT` is the absolute dotfiles repo root and is exposed read-only inside Firejail.
- `DOTFILES_TEST_TMP` is the per-case writable temp root. Passing tests remove it; failing tests keep it and print the path.
- `DOTFILES_TEST_NO_FIREJAIL=1` disables Firejail only for harness debugging.
- `DOTFILES_TEST_ALLOW_NESTED_FIREJAIL=1` bypasses the nested-Firejail guard only for explicit experiments after investigation.
- Exit code `0` means pass, `77` means skip, and any other non-zero code means fail.
- The runner executes each test with cwd set to `DOTFILES_TEST_ROOT`.
- Discovery currently scans shell files named `*.sh` one directory below `tests/`, such as `tests/nvim/example.sh`.

Minimal shell test shape:

```sh
#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: example
# dotfiles-test-case: feature-loads
# dotfiles-test-case: feature-behaves

case "${DOTFILES_TEST_CASE:-}" in
feature-loads)
    command-that-loads
    ;;
feature-behaves)
    fixture="${DOTFILES_TEST_TMP}/fixture"
    mkdir -p "$fixture"
    command-that-asserts-behavior "$fixture"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
```
