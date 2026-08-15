#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: hypothesis kwallet ansible pkm fast
# dotfiles-test-case: hypothesis-keyrings-defined-in-pkm-defaults
# dotfiles-test-case: hypothesis-keyrings-wired-into-setup-kwallet
# dotfiles-test-case: hypexport-script-uses-kwallet-conventions

# Purpose: Verify the hypothesis credentials are provisioned through the
# project's KWallet conventions: defined as keyring defaults in the 40-PKM
# role, merged into the setup-kwallet keyrings fact, and consumed by the
# hypexport export script.

pkm_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/defaults/main.yml"
security_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/190-setup-security-tools.archlinux.yml"
hypexport_script="${DOTFILES_TEST_ROOT}/PKM/bin/hpi-hypexport.sh"

case "${DOTFILES_TEST_CASE:-}" in
hypothesis-keyrings-defined-in-pkm-defaults)
    rg -q '^hypothesis_username_keyring:$' "$pkm_defaults"
    rg -q '^hypothesis_password_keyring:$' "$pkm_defaults"
    rg -q 'folder: pkm' "$pkm_defaults"
    rg -q 'passkey: hypothesis-username' "$pkm_defaults"
    rg -q 'passkey: hypothesis-password' "$pkm_defaults"
    rg -q 'wallet: kdewallet' "$pkm_defaults"
    ;;
hypothesis-keyrings-wired-into-setup-kwallet)
    rg -q 'set hypothesis keyrings facts' "$security_tasks"
    rg -q 'hypothesis_username_keyring' "$security_tasks"
    rg -q 'hypothesis_password_keyring' "$security_tasks"
    rg -q 'union\(' "$security_tasks"
    ;;
hypexport-script-uses-kwallet-conventions)
    bash -n "$hypexport_script"
    rg -q 'kwallet-query --folder' "$hypexport_script"
    rg -q 'hypothesis-username' "$hypexport_script"
    rg -q 'hypothesis-password' "$hypexport_script"
    refute rg -q 'data/secrets/hypothesis' "$hypexport_script"
    refute rg -q 'gpg --decrypt' "$hypexport_script"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
