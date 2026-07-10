#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks nvidia xorg shell firejail
# dotfiles-test-case: nvidia-xorg-enables-gpu-screens
# dotfiles-test-case: sddm-xsetup-uses-dynamic-nvidia-provider

# Purpose: Keep the reverse PRIME config aligned with the HDMI output path.

xorg_config="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/nvidia/80-igpu-primary-egpu-offload.conf"
xsetup_template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/sddm/Xsetup"

case "${DOTFILES_TEST_CASE:-}" in
nvidia-xorg-enables-gpu-screens)
    grep -q 'Section "ServerLayout"' "$xorg_config"
    grep -q 'Option     "AllowNVIDIAGPUScreens"' "$xorg_config"
    grep -q 'Inactive   "Device1"' "$xorg_config"
    grep -q 'Identifier     "Screen1"' "$xorg_config"
    grep -q 'Option         "AllowEmptyInitialConfiguration"' "$xorg_config"
    ;;
sddm-xsetup-uses-dynamic-nvidia-provider)
    grep -q 'xrandr --listproviders' "$xsetup_template"
    grep -q 'name:NVIDIA' "$xsetup_template"
    grep -q 'xrandr --setprovideroutputsource "$nvidia_provider" modesetting' "$xsetup_template"
    if grep -q 'setprovideroutputsource modesetting NVIDIA-0' "$xsetup_template"; then
        printf 'Xsetup must not hardcode NVIDIA-0 for reverse PRIME\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
