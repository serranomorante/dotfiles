#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: peripherals
# dotfiles-test-tags: peripherals keyd pedalboard picker shell
# dotfiles-test-case: pedalboard-profile-picker-keyd-contract

# Purpose: Verify the global keyd/Kitty contract for the Pedalboard MIDI profile picker.

keyd_template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/keyd-default.conf"
keyd_observer="${DOTFILES_TEST_ROOT}/peripherals/bin/keyd-observer"
dwm_custom_patch="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/custom.patch"
pedalboard_profiles_file="${DOTFILES_TEST_ROOT}/audio/dot-local/share/dotfiles/pedalboard-midi-profiles.tsv"

case "${DOTFILES_TEST_CASE:-}" in
pedalboard-profile-picker-keyd-contract)
    rg -q '^b = layer\(signal_open_pedalboard_profiles\)$' "$keyd_template"
    rg -q '^\[signal_open_pedalboard_profiles\]$' "$keyd_template"
    rg -q 'pedalboard_profile_picker="\$HOME/\.local/bin/pedalboard-midi-profile-picker"' "$keyd_observer"
    rg -q 'run_open_pedalboard_profile_picker' "$keyd_observer"
    rg -q 'signal_open_pedalboard_profiles' "$keyd_observer"
    rg -q 'kitty-pedalboard-profiles' "$dwm_custom_patch"
    grep -Fqx $'3\tdesktop\tdesktop\t16\t4\t80\t81\tmomentary\tmomentary\tdesktop\t-' "$pedalboard_profiles_file"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
