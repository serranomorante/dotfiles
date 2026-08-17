#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: term
# dotfiles-test-tags: term kitty dwm shell
# dotfiles-test-case: kitty-scratchpad-syntax
# dotfiles-test-case: kitty-scratchpad-dwm-contract

# Purpose: Guard the dwm-bound scratchpad quick-access terminal contract.

wrapper="${DOTFILES_TEST_ROOT}/term/bin/kitty-scratchpad-quick-access"
dwm_custom_patch="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/custom.patch"
dwm_hide_patch="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/add-dwm-scratchpad-hide-on-close.patch"
compositor_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/100-setup-compositor.archlinux.yml"

case "${DOTFILES_TEST_CASE:-}" in
kitty-scratchpad-syntax)
    sh -n "$wrapper"
    ;;
kitty-scratchpad-dwm-contract)
    rg -q '^exec kitten quick-access-terminal \\$' "$wrapper"
    rg -q -- '--instance-group="scratchpad"' "$wrapper"
    rg -q -- '--override app_id=kitty-scratchpad' "$wrapper"
    rg -q -- '"kitty-scratchpad",.*FULLMON,FULLMON,FULLMON,FULLMON' "$dwm_custom_patch"
    rg -q -- 'scratchcmd\[\] = \{ "kitty-scratchpad-quick-access", NULL \}' "$dwm_custom_patch"
    rg -q -- 'XK_Return, spawn,          \{\.v = scratchcmd \}' "$dwm_custom_patch"
    rg -q -- '"kitty-scratchpad"' "$dwm_hide_patch"
    rg -q -- '\.v = scratchcmd' "$dwm_hide_patch"
    rg -q -- 'spawn\(&a\)' "$dwm_hide_patch"
    rg -q -- 'add-dwm-scratchpad-hide-on-close.patch' "$compositor_tasks"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
