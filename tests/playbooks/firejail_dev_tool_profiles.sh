#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: firejail static fast
# dotfiles-test-case: firejail-dev-tool-profiles-avoid-broad-xdg
# dotfiles-test-case: firejail-dev-nvim-avoids-global-nvim-state
# dotfiles-test-case: firejail-promnesia-exposes-stow-target

# Purpose: Static guardrails for dev-tool Firejail profile path exposure.

root=${DOTFILES_TEST_ROOT}

case "${DOTFILES_TEST_CASE:-}" in
firejail-dev-tool-profiles-avoid-broad-xdg)
    for profile in \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node-ansible.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node-volta-bootstrap.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-php.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-php-ansible.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-py.profile"; do
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.cache([[:space:]]|$)' "$profile"; then
            printf 'broad cache whitelist in %s\n' "$profile" >&2
            exit 1
        fi
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.local/(state|share)([[:space:]]|$)' "$profile"; then
            printf 'broad local state/share whitelist in %s\n' "$profile" >&2
            exit 1
        fi
    done
    ;;
firejail-dev-nvim-avoids-global-nvim-state)
    profile="$root/playbooks/roles/20-dev-tools/templates/dev-editor-shell-common.inc"
    for path in \
        '${HOME}/.cache/nvim' \
        '${HOME}/.local/state/nvim' \
        '${HOME}/.local/share/nvim'; do
        if grep -Fqx "whitelist ${path}" "$profile"; then
            printf 'global writable Neovim state whitelist remains: %s\n' "$path" >&2
            exit 1
        fi
    done
    ;;
firejail-promnesia-exposes-stow-target)
    profile="$root/playbooks/roles/20-dev-tools/templates/fj-py-promnesia.profile"
    for path in \
        'whitelist-ro ${HOME}/dotfiles/PKM/dot-config/my' \
        'whitelist-ro ${HOME}/dotfiles/PKM/dot-config/promnesia'; do
        if ! grep -Fqx "$path" "$profile"; then
            printf 'Promnesia profile does not expose stowed config target: %s\n' "$path" >&2
            exit 1
        fi
    done
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
