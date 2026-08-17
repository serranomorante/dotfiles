#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities ansible stow git python fast
# dotfiles-test-case: dotfiles-system-apply-syntax
# dotfiles-test-case: dotfiles-system-apply-maps-commit-to-commands
# dotfiles-test-case: dotfiles-system-apply-prepends-aur-prep-tag
# dotfiles-test-case: dotfiles-system-apply-unresolvable-commit-fails

# Purpose: Verify the commit -> Stow/Ansible command mapping contract without
# invoking Stow, Ansible, or the active dotfiles repo.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-system-apply"

make_fake_repo() {
    local repo="${DOTFILES_TEST_TMP}/repo"
    mkdir -p "${repo}/playbooks/roles/10-system-tools/defaults/main"

    cat >"${repo}/playbooks/roles/10-system-tools/defaults/main/main.vars.yml" <<'YAML'
---
dotfiles_public_stow_packages:
  - PKM
  - utilities
YAML

    cat >"${repo}/playbooks/tools.yml" <<'YAML'
---
- hosts: localhost
  tasks: []
YAML

    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Dotfiles Test"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" add .
    git -C "$repo" commit -q -m "chore: repo infra"

    mkdir -p "${repo}/PKM/dot-config/systemd/user"
    mkdir -p "${repo}/playbooks/roles/40-PKM/tasks"
    mkdir -p "${repo}/playbooks/roles/40-PKM/templates"

    cat >"${repo}/playbooks/hypothesis-reindex.yml" <<'YAML'
---
- hosts: localhost
  tasks: []
YAML

    cat >"${repo}/playbooks/roles/40-PKM/tasks/20-setup-hpi.archlinux.yml" <<'YAML'
---
- name: install hpi patch
  ansible.builtin.template:
    src: "{{ item }}"
    dest: "/tmp/{{ item }}"
  loop:
    - hypothesis_h.patch
YAML

    printf 'patched\n' >"${repo}/playbooks/roles/40-PKM/templates/hypothesis_h.patch"
    printf 'unit\n' >"${repo}/PKM/dot-config/systemd/user/foo.service"

    git -C "$repo" add .
    git -C "$repo" commit -q -m "feat(pkm): add hpi patch and stow unit"

    printf '%s\n' "$repo"
}

make_fake_aur_repo() {
    local repo="${DOTFILES_TEST_TMP}/aur-repo"
    mkdir -p "${repo}/playbooks/roles/20-dev-tools/defaults/main"
    mkdir -p "${repo}/playbooks/roles/20-dev-tools/tasks"
    mkdir -p "${repo}/playbooks/roles/10-system-tools/tasks"

    cat >"${repo}/playbooks/roles/20-dev-tools/defaults/main/main.vars.yml" <<'YAML'
---
dotfiles_public_stow_packages: []
YAML

    cat >"${repo}/playbooks/tools.yml" <<'YAML'
---
- hosts: localhost
  tasks: []
YAML

    cat >"${repo}/playbooks/roles/10-system-tools/tasks/20-setup-aur.archlinux.yml" <<'YAML'
---
- name: "[{{ user_os }}] AUR: configure local package repository"
  ansible.builtin.command:
    argv:
      - repo-add
      - "{{ arch_aur_local_repo_path }}/{{ arch_aur_local_repo_name }}.db.tar.gz"
YAML

    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Dotfiles Test"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" add .
    git -C "$repo" commit -q -m "chore: repo infra"

    cat >"${repo}/playbooks/roles/20-dev-tools/tasks/90-setup-git-tools.archlinux.yml" <<'YAML'
---
- name: "[{{ user_os }}] Setup git tools: ensure local AUR packages"
  ansible.builtin.include_tasks: "{{ ansible_facts.env.HOME }}/dotfiles/playbooks/roles/10-system-tools/tasks/install-local-aur-packages.archlinux.yml"
  vars:
    aur_local_packages: lazygit-git
YAML

    git -C "$repo" add .
    git -C "$repo" commit -q -m "feat(dev-tools): add local AUR package"

    printf '%s\n' "$repo"
}

case "${DOTFILES_TEST_CASE:-}" in
dotfiles-system-apply-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
dotfiles-system-apply-maps-commit-to-commands)
    repo=$(make_fake_repo)
    sha=$(git -C "$repo" rev-parse HEAD)

    "$script_under_test" --repo "$repo" "$sha" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q '^dotfiles-stow PKM' "${DOTFILES_TEST_TMP}/stdout"
    rg -q 'ansible-playbook hypothesis-reindex\.yml -l localhost -K' "${DOTFILES_TEST_TMP}/stdout"
    rg -q -- '--tags 40-20' "${DOTFILES_TEST_TMP}/stdout"
    ! rg -q -- '--tags 40-10' "${DOTFILES_TEST_TMP}/stdout"
    ! rg -q 'ansible-playbook tools\.yml -l localhost -K 2>&1' "${DOTFILES_TEST_TMP}/stdout"
    ;;
dotfiles-system-apply-prepends-aur-prep-tag)
    repo=$(make_fake_aur_repo)
    sha=$(git -C "$repo" rev-parse HEAD)

    "$script_under_test" --repo "$repo" "$sha" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q -- '--tags 10-20,20-90' "${DOTFILES_TEST_TMP}/stdout"
    ;;
dotfiles-system-apply-unresolvable-commit-fails)
    repo=$(make_fake_repo)

    if "$script_under_test" --repo "$repo" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'expected unresolvable commit to fail\n' >&2
        exit 1
    fi

    rg -q 'cannot resolve' "${DOTFILES_TEST_TMP}/stderr"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
