#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: term
# dotfiles-test-tags: term kitty shell
# dotfiles-test-case: kitty-dmenu-syntax
# dotfiles-test-case: kitty-dmenu-project-plain-root-lists-children
# dotfiles-test-case: kitty-dmenu-project-glob-lists-direct-matches
# dotfiles-test-case: kitty-dmenu-project-glob-keeps-plain-root-children

# Purpose: Verify project-directory discovery behavior for kitty-dmenu.

script_under_test="${DOTFILES_TEST_ROOT}/term/bin/kitty-dmenu"

source_kitty_dmenu() {
    local home="${DOTFILES_TEST_TMP}/home"
    local old_home=$HOME

    mkdir -p "$home"
    ln -s "$DOTFILES_TEST_ROOT" "${home}/dotfiles"
    HOME=$home
    source "$script_under_test"
    HOME=$old_home
}

assert_lines_equal() {
    local expected=$1
    local actual=$2

    if [[ "$actual" != "$expected" ]]; then
        printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

make_project_fixture() {
    local fixture=$1

    mkdir -p \
        "${fixture}/dotfiles" \
        "${fixture}/dotfiles/nvim" \
        "${fixture}/dotfiles/playbooks" \
        "${fixture}/dotfiles-test" \
        "${fixture}/dotfiles/otherlevel/etc" \
        "${fixture}/root/child"
}

case "${DOTFILES_TEST_CASE:-}" in
kitty-dmenu-syntax)
    bash -n "$script_under_test"
    ;;
kitty-dmenu-project-plain-root-lists-children)
    source_kitty_dmenu

    fixture="${DOTFILES_TEST_TMP}/projects"
    make_project_fixture "$fixture"

    project_roots=(
        "${fixture}/dotfiles"
        "${fixture}/root"
    )

    expected=$(printf '%s\n' \
        "${fixture}/dotfiles/nvim" \
        "${fixture}/dotfiles/otherlevel" \
        "${fixture}/dotfiles/playbooks" \
        "${fixture}/root/child")
    actual=$(build_project_dirs | sort)

    assert_lines_equal "$expected" "$actual"
    ;;
kitty-dmenu-project-glob-lists-direct-matches)
    source_kitty_dmenu

    fixture="${DOTFILES_TEST_TMP}/projects"
    make_project_fixture "$fixture"

    project_roots=(
        "${fixture}/dotfiles*"
    )

    expected=$(printf '%s\n' \
        "${fixture}/dotfiles" \
        "${fixture}/dotfiles-test")
    actual=$(build_project_dirs | sort)

    assert_lines_equal "$expected" "$actual"
    ;;
kitty-dmenu-project-glob-keeps-plain-root-children)
    source_kitty_dmenu

    fixture="${DOTFILES_TEST_TMP}/projects"
    make_project_fixture "$fixture"

    project_roots=(
        "${fixture}/dotfiles"
        "${fixture}/dotfiles*"
        "${fixture}/root"
    )

    expected=$(printf '%s\n' \
        "${fixture}/dotfiles" \
        "${fixture}/dotfiles-test" \
        "${fixture}/dotfiles/nvim" \
        "${fixture}/dotfiles/otherlevel" \
        "${fixture}/dotfiles/playbooks" \
        "${fixture}/root/child")
    actual=$(build_project_dirs | sort)

    assert_lines_equal "$expected" "$actual"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
