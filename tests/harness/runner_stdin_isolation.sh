#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: harness
# dotfiles-test-tags: harness runner stdin
# dotfiles-test-firejail: disabled
# dotfiles-test-case: runner-does-not-truncate-discovery-on-stdin-eater

# Purpose: Guard against the runner silently skipping discovered test files when
# an earlier test consumes stdin. Each test runs with stdin redirected from
# /dev/null, and the discovered file list is materialized up front so a child
# cannot drain the discovery pipe. If either guarantee regresses, the fixtures
# in tests/harness-fixtures/ stop reporting their full count.

runner="${DOTFILES_TEST_ROOT}/tests/run"
fixtures_dir="${DOTFILES_TEST_ROOT}/tests/harness-fixtures"

case "${DOTFILES_TEST_CASE:-}" in
runner-does-not-truncate-discovery-on-stdin-eater)
    if [[ ! -x "$runner" ]]; then
        printf 'runner not executable: %s\n' "$runner" >&2
        exit 2
    fi
    if [[ ! -f "${fixtures_dir}/10_stdin_eater.sh" || ! -f "${fixtures_dir}/20_after_stdin_eater.sh" ]]; then
        printf 'missing stdin-eater fixtures under %s\n' "$fixtures_dir" >&2
        exit 2
    fi

    out="${DOTFILES_TEST_TMP}/run.out"
    "${runner}" --unit harness-fixtures --allow-skips >"$out" 2>&1 || {
        printf 'nested runner failed for unit harness-fixtures\n' >&2
        sed 's/^/  /' "$out" >&2
        exit 1
    }

    grep -q 'PASS harness-fixture-stdin-eater' "$out" || {
        printf 'stdin-eater fixture did not pass\n' >&2
        sed 's/^/  /' "$out" >&2
        exit 1
    }
    grep -q 'PASS harness-fixture-runs-after-stdin-eater' "$out" || {
        printf 'fixture after stdin-eater did not run: discovery truncated\n' >&2
        sed 's/^/  /' "$out" >&2
        exit 1
    }
    grep -q 'Summary: 2 passed, 0 skipped, 0 failed, 2 total' "$out" || {
        printf 'unexpected summary\n' >&2
        sed 's/^/  /' "$out" >&2
        exit 1
    }
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
