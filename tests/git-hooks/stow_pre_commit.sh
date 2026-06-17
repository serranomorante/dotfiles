#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: git-hooks
# dotfiles-test-tags: git stow hooks firejail
# dotfiles-test-case: stow-pre-commit-allows-linked-new-file
# dotfiles-test-case: stow-pre-commit-blocks-unlinked-new-file
# dotfiles-test-case: dotfiles-stow-help-documents-check-mode
# dotfiles-test-case: dotfiles-stow-recreate-switches-stow-dir
# dotfiles-test-case: dotfiles-stow-recreate-finds-current-stow-dir
# dotfiles-test-case: dotfiles-stow-recreate-restows-managed-dir

# Purpose: Verify the pre-commit Stow guard checks newly added package files.

make_fixture_repo() {
    local repo=$1

    mkdir -p \
        "${repo}/utilities/git-hooks/lib" \
        "${repo}/playbooks/roles/10-system-tools/defaults/main" \
        "${repo}/pkg/dot-config/app"

    cp "${DOTFILES_TEST_ROOT}/utilities/git-hooks/pre-commit" "${repo}/utilities/git-hooks/pre-commit"
    cp "${DOTFILES_TEST_ROOT}/utilities/git-hooks/lib/stow-check" "${repo}/utilities/git-hooks/lib/stow-check"
    chmod +x "${repo}/utilities/git-hooks/pre-commit"

    cat >"${repo}/playbooks/roles/10-system-tools/defaults/main/main.vars.yml" <<'YAML'
---
dotfiles_stow_options:
  - --dotfiles
  - --no-folding
dotfiles_stow_ignore_patterns: []
dotfiles_public_stow_packages:
  - pkg
dotfiles_private_stow_packages: []
dotfiles_otherlinux_stow_packages: []
dotfiles_agent_context_source_name: AGENTS.md
dotfiles_agent_context_symlink_names: []
dotfiles_private_agent_context_doc_paths: []
YAML

    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name "Dotfiles Test"
    git -C "$repo" config core.hooksPath utilities/git-hooks
    git -C "$repo" add utilities playbooks
    git -C "$repo" commit -q --no-verify -m "test: base"
}

run_commit() {
    local repo=$1
    local home=$2
    shift 2

    HOME="$home" git -C "$repo" "$@"
}

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

    ansible localhost -m ansible.builtin.template -a "src=${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/dotfiles-stow dest=${dest} mode=0755" -e "@${vars_file}" >/dev/null
}

make_stow_package() {
    local repo=$1
    local value=$2

    mkdir -p "${repo}/pkg/dot-config/app"
    printf '%s\n' "$value" >"${repo}/pkg/dot-config/app/name"
}

case "${DOTFILES_TEST_CASE:-}" in
stow-pre-commit-allows-linked-new-file)
    repo="${DOTFILES_TEST_TMP}/repo"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    make_fixture_repo "$repo"

    printf 'linked\n' >"${repo}/pkg/dot-config/app/linked"
    stow --dotfiles --no-folding --target="$home" --dir="$repo" pkg
    run_commit "$repo" "$home" add pkg/dot-config/app/linked
    run_commit "$repo" "$home" commit -q -m "test: linked file"
    ;;
stow-pre-commit-blocks-unlinked-new-file)
    repo="${DOTFILES_TEST_TMP}/repo"
    home="${DOTFILES_TEST_TMP}/home"
    output="${DOTFILES_TEST_TMP}/commit.out"
    mkdir -p "$home"
    make_fixture_repo "$repo"

    printf 'unlinked\n' >"${repo}/pkg/dot-config/app/unlinked"
    run_commit "$repo" "$home" add pkg/dot-config/app/unlinked

    if run_commit "$repo" "$home" commit -m "test: unlinked file" >"$output" 2>&1; then
        printf '%s\n' "commit unexpectedly succeeded" >&2
        exit 1
    fi

    rg -q "pkg/dot-config/app/unlinked" "$output"
    rg -q "dotfiles-stow pkg" "$output"
    ;;
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
