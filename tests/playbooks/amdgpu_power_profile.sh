#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks amdgpu systemd shell fast
# dotfiles-test-case: amdgpu-power-profile-syntax
# dotfiles-test-case: amdgpu-power-profile-applies-balanced-and-auto
# dotfiles-test-case: amdgpu-power-profile-is-in-normal-setup

# Purpose: Verify the managed AMDGPU boot power policy.

helper="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/amdgpu-power-profile"
service="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/amdgpu-power-profile.service"
main_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/main.yml"
profile_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/66-setup-amdgpu-power-profile.archlinux.yml"
defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/defaults/main/main.vars.yml"

case "${DOTFILES_TEST_CASE:-}" in
amdgpu-power-profile-syntax)
    sh -n "$helper"
    grep -q 'AMDGPU_POWER_DPM_STATE={{ arch_amdgpu_power_dpm_state }}' "$service"
    grep -q 'AMDGPU_FORCE_PERFORMANCE_LEVEL={{ arch_amdgpu_force_performance_level }}' "$service"
    grep -Fxq 'arch_amdgpu_power_dpm_state: balanced' "$defaults"
    grep -Fxq 'arch_amdgpu_force_performance_level: auto' "$defaults"
    ;;
amdgpu-power-profile-applies-balanced-and-auto)
    sysfs="${DOTFILES_TEST_TMP}/sys"
    amd="${sysfs}/class/drm/card1/device"
    nvidia="${sysfs}/class/drm/card0/device"
    mkdir -p "$amd" "$nvidia"
    printf '0x1002\n' >"${amd}/vendor"
    printf 'performance\n' >"${amd}/power_dpm_state"
    printf 'auto\n' >"${amd}/power_dpm_force_performance_level"
    printf '0x10de\n' >"${nvidia}/vendor"
    printf 'performance\n' >"${nvidia}/power_dpm_state"
    output="$(AMDGPU_POWER_PROFILE_SYSFS_ROOT="$sysfs" "$helper" balanced auto)"
    [[ "$output" == changed ]]
    grep -Fxq 'balanced' "${amd}/power_dpm_state"
    grep -Fxq 'auto' "${amd}/power_dpm_force_performance_level"
    grep -Fxq 'performance' "${nvidia}/power_dpm_state"
    ;;
amdgpu-power-profile-is-in-normal-setup)
    grep -q '66-setup-amdgpu-power-profile.{{ user_os }}.yml' "$main_tasks"
    grep -q 'tags: \["10-60", "10-60-amdgpu-power-profile"\]' "$main_tasks"
    grep -A7 'Setup AMDGPU power profile is configured' "$main_tasks" | grep -q 'apply:'
    grep -A7 'Setup AMDGPU power profile is configured' "$main_tasks" | grep -q '10-60-amdgpu-power-profile'
    grep -q 'amdgpu-power-profile.service' "$profile_tasks"
    if grep -q 'ansible.builtin.package\|aur_local_packages' "$profile_tasks"; then
        printf '10-60-amdgpu-power-profile must not run package installation tasks\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
