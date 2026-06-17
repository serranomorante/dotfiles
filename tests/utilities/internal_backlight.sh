#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities displays shell
# dotfiles-test-case: internal-backlight-syntax
# dotfiles-test-case: internal-backlight-up-recovers-bogus-scaled-value
# dotfiles-test-case: internal-backlight-down-preserves-raw-scale

# Purpose: Verify the raw amdgpu backlight helper used by keyd brightness keys.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/internal-backlight"

write_fake_backlight() {
    local brightness=$1
    local backlight="${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1/amdgpu_bl1"

    mkdir -p "$backlight"
    printf '%s\n' "$brightness" >"$backlight/brightness"
    printf '%s\n' 65535 >"$backlight/max_brightness"
}

run_internal_backlight() {
    INTERNAL_BACKLIGHT_SYSFS_ROOT="${DOTFILES_TEST_TMP}/sys" "$script_under_test" "$1"
}

case "${DOTFILES_TEST_CASE:-}" in
internal-backlight-syntax)
    bash -n "$script_under_test"
    ;;
internal-backlight-up-recovers-bogus-scaled-value)
    write_fake_backlight 80
    run_internal_backlight up
    grep -q '^36043$' "${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1/amdgpu_bl1/brightness"
    ;;
internal-backlight-down-preserves-raw-scale)
    write_fake_backlight 40000
    run_internal_backlight down
    grep -q '^36724$' "${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1/amdgpu_bl1/brightness"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
