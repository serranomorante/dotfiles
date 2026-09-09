#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities marks shell
# dotfiles-test-case: marks-label-syntax
# dotfiles-test-case: marks-label-set-get-clear
# dotfiles-test-case: marks-label-scope-isolation
# dotfiles-test-case: marks-label-list-format

# Purpose: Verify the shared named-mark label store CLI and library.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/marks-label"
common="${DOTFILES_TEST_ROOT}/utilities/bin/marks-common.sh"
marks_dir="${DOTFILES_TEST_TMP}/state/dotfiles/marks"

case "${DOTFILES_TEST_CASE:-}" in
marks-label-syntax)
    sh -n "$script_under_test"
    sh -n "$common"
    ;;
marks-label-set-get-clear)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/state"
    "$script_under_test" set scope1 a 'hello world'
    [ "$("$script_under_test" get scope1 a)" = 'hello world' ]

    "$script_under_test" set scope1 b '   padded   label   '
    [ "$("$script_under_test" get scope1 b)" = 'padded   label' ]

    "$script_under_test" set scope1 a 'second'
    [ "$("$script_under_test" get scope1 a)" = 'second' ]
    [ "$(wc -l <"${marks_dir}/scope1.labels")" = 2 ]

    "$script_under_test" clear scope1 a
    [ -z "$("$script_under_test" get scope1 a)" ]
    [ "$("$script_under_test" get scope1 b)" = 'padded   label' ]

    "$script_under_test" clear scope1 b
    refute test -e "${marks_dir}/scope1.labels"
    ;;
marks-label-scope-isolation)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/state"
    "$script_under_test" set alpha a 'in alpha'
    "$script_under_test" set beta a 'in beta'
    [ "$("$script_under_test" get alpha a)" = 'in alpha' ]
    [ "$("$script_under_test" get beta a)" = 'in beta' ]
    refute grep -q 'in beta' "${marks_dir}/alpha.labels"
    ;;
marks-label-list-format)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/state"
    "$script_under_test" set scope a 'first'
    "$script_under_test" set scope b 'second one'
    "$script_under_test" list scope >"${DOTFILES_TEST_TMP}/out"
    grep -Fqx $'a\tfirst' "${DOTFILES_TEST_TMP}/out"
    grep -Fqx $'b\tsecond one' "${DOTFILES_TEST_TMP}/out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
