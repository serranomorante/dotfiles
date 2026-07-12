#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks nvidia xorg shell firejail
# dotfiles-test-case: nvidia-xorg-enables-gpu-screens
# dotfiles-test-case: nvidia-default-profile-is-offload-only
# dotfiles-test-case: nvidia-profile-tag-runs-in-normal-setup
# dotfiles-test-case: nvidia-profile-tag-does-not-run-package-tasks
# dotfiles-test-case: nvidia-offload-profile-removes-reverse-prime-config
# dotfiles-test-case: sddm-xsetup-gates-reverse-prime
# dotfiles-test-case: sddm-xsetup-uses-dynamic-nvidia-provider

# Purpose: Keep the reverse PRIME config aligned with the HDMI output path.

xorg_config="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/nvidia/80-igpu-primary-egpu-offload.conf"
xsetup_template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/sddm/Xsetup"
main_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/main.yml"
nvidia_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/60-setup-nvidia-tools.archlinux.yml"
nvidia_profile_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/65-setup-nvidia-display-profile.archlinux.yml"
nvidia_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/defaults/main/main.vars.yml"

case "${DOTFILES_TEST_CASE:-}" in
nvidia-xorg-enables-gpu-screens)
    grep -q 'Section "ServerLayout"' "$xorg_config"
    grep -q 'Option     "AllowNVIDIAGPUScreens"' "$xorg_config"
    grep -q 'Inactive   "Device1"' "$xorg_config"
    grep -q 'Identifier     "Screen1"' "$xorg_config"
    grep -q 'Option         "AllowEmptyInitialConfiguration"' "$xorg_config"
    ;;
nvidia-default-profile-is-offload-only)
    grep -Fxq 'arch_nvidia_display_profile: offload_only' "$nvidia_defaults"
    ;;
nvidia-profile-tag-runs-in-normal-setup)
    grep -q 'tags: \["10-60", "10-60-nvidia-profile"\]' "$main_tasks"
    grep -q '65-setup-nvidia-display-profile.{{ user_os }}.yml' "$main_tasks"
    if grep -A3 '10-60-nvidia-profile' "$main_tasks" | grep -q 'never'; then
        printf '10-60-nvidia-profile must run during normal 10-system-tools setup\n' >&2
        exit 1
    fi
    grep -q 'refresh SDDM Xsetup' "$nvidia_profile_tasks"
    ;;
nvidia-profile-tag-does-not-run-package-tasks)
    refute_package_tasks='package:\|aur_local_packages'
    if grep -q "$refute_package_tasks" "$nvidia_profile_tasks"; then
        printf '10-60-nvidia-profile must not run package installation tasks\n' >&2
        exit 1
    fi
    ;;
nvidia-offload-profile-removes-reverse-prime-config)
    grep -q "arch_nvidia_display_profile == 'offload_only'" "$nvidia_profile_tasks"
    grep -q '80-igpu-primary-egpu-offload.conf' "$nvidia_profile_tasks"
    grep -q 'state: absent' "$nvidia_profile_tasks"
    grep -q "state: \"{{ 'started' if arch_nvidia_display_profile == 'reverse_prime' else 'stopped' }}\"" "$nvidia_profile_tasks"
    ;;
sddm-xsetup-gates-reverse-prime)
    grep -q "arch_nvidia_display_profile | default('offload_only') == 'reverse_prime'" "$xsetup_template"
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
