#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: git-hooks
# dotfiles-test-tags: git stow firejail
# dotfiles-test-case: dotfiles-stow-help-documents-check-mode
# dotfiles-test-case: dotfiles-stow-recreate-switches-stow-dir
# dotfiles-test-case: dotfiles-stow-recreate-finds-current-stow-dir
# dotfiles-test-case: dotfiles-stow-recreate-restows-managed-dir

# Purpose: Verify the dotfiles-stow wrapper renders and recreates Stow links correctly.

render_dotfiles_stow() {
    local home=$1
    local dest=$2
    local vars_file="${DOTFILES_TEST_TMP}/dotfiles-stow-vars.yml"

    command -v ansible >/dev/null 2>&1 || {
        printf 'ansible is not available\n' >&2
        exit 77
    }

    cat >"$vars_file" <<YAML
---
ansible_facts:
  env:
    HOME: "$home"
dotfiles_stow_options:
  - --dotfiles
  - --no-folding
dotfiles_stow_ignore_patterns: []
dotfiles_agent_context_source_name: AGENTS.md
dotfiles_agent_context_symlink_names: []
dotfiles_private_agent_context_doc_paths: []
YAML

    ansible -c local localhost -m ansible.builtin.template -a "src=${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/dotfiles-stow dest=${dest} mode=0755" -e "@${vars_file}" >/dev/null
}

make_stow_package() {
    local repo=$1
    local value=$2

    mkdir -p "${repo}/pkg/dot-config/app"
    printf '%s\n' "$value" >"${repo}/pkg/dot-config/app/name"
}

case "${DOTFILES_TEST_CASE:-}" in
dotfiles-stow-help-documents-check-mode)
    template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/dotfiles-stow"

    rg -q "dotfiles-stow --check-stowed FILE" "$template"
    rg -q "dotfiles-stow --check-stowed-from FILE" "$template"
    rg -q "dotfiles-stow --recreate" "$template"
    rg -q -- "--print-stow-dir" "$template"
    rg -q "Stow defaults applied by this wrapper" "$template"
    ;;
dotfiles-stow-recreate-switches-stow-dir)
    home="${DOTFILES_TEST_TMP}/home"
    managed="${home}/dotfiles"
    alternate="${home}/dotfiles-test"
    wrapper="${DOTFILES_TEST_TMP}/dotfiles-stow"
    mkdir -p "$home"
    make_stow_package "$managed" managed
    make_stow_package "$alternate" alternate
    render_dotfiles_stow "$home" "$wrapper"

    HOME="$home" "$wrapper" pkg
    [[ $(<"${home}/.config/app/name") == managed ]]
    [[ $(readlink "${home}/.config/app/name") == *dotfiles/pkg/dot-config/app/name ]]

    HOME="$home" "$wrapper" --recreate --dir="$alternate" pkg
    [[ $(<"${home}/.config/app/name") == alternate ]]
    [[ $(readlink "${home}/.config/app/name") == *dotfiles-test/pkg/dot-config/app/name ]]
    ;;
dotfiles-stow-recreate-finds-current-stow-dir)
    home="${DOTFILES_TEST_TMP}/home"
    managed="${home}/dotfiles"
    alternate="${home}/dotfiles-test"
    wrapper="${DOTFILES_TEST_TMP}/dotfiles-stow"
    mkdir -p "$home"
    make_stow_package "$managed" managed
    make_stow_package "$alternate" alternate
    render_dotfiles_stow "$home" "$wrapper"

    HOME="$home" "$wrapper" --dir="$alternate" pkg
    [[ $(<"${home}/.config/app/name") == alternate ]]
    [[ $(readlink "${home}/.config/app/name") == *dotfiles-test/pkg/dot-config/app/name ]]

    HOME="$home" "$wrapper" --recreate pkg
    [[ $(<"${home}/.config/app/name") == managed ]]
    [[ $(readlink "${home}/.config/app/name") == *dotfiles/pkg/dot-config/app/name ]]
    ;;
dotfiles-stow-recreate-restows-managed-dir)
    home="${DOTFILES_TEST_TMP}/home"
    managed="${home}/dotfiles"
    wrapper="${DOTFILES_TEST_TMP}/dotfiles-stow"
    mkdir -p "$home"
    make_stow_package "$managed" managed
    render_dotfiles_stow "$home" "$wrapper"

    HOME="$home" "$wrapper" --recreate pkg
    [[ $(<"${home}/.config/app/name") == managed ]]
    [[ $(readlink "${home}/.config/app/name") == *dotfiles/pkg/dot-config/app/name ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
