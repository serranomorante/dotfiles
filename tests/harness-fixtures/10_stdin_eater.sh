#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: harness-fixtures
# dotfiles-test-firejail: disabled
# dotfiles-test-case: harness-fixture-stdin-eater

# Purpose: Regression fixture that consumes all of stdin to EOF. When the
# runner let a test inherit the discovery pipe as stdin, this fixture drained
# the pipe and silently truncated the discovered file list.

case "${DOTFILES_TEST_CASE:-}" in
harness-fixture-stdin-eater)
    cat >/dev/null
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
