#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: harness-fixtures
# dotfiles-test-firejail: disabled
# dotfiles-test-case: harness-fixture-runs-after-stdin-eater

# Purpose: Regression fixture that sorts after 10_stdin_eater.sh. If the stdin
# eater truncated the discovered file list, this file would never run and the
# harness assertion below would fail.

case "${DOTFILES_TEST_CASE:-}" in
harness-fixture-runs-after-stdin-eater)
    :
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
