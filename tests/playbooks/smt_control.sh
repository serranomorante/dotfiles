#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks systemd shell fast
# dotfiles-test-case: smt-control-syntax
# dotfiles-test-case: smt-control-writes-on-and-off
# dotfiles-test-case: smt-control-is-on-demand-in-audio-setup

# Purpose: Verify the managed SMT (hyper-threading) REAPER-session policy.

helper="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/smt-control"
service="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/smt-control.service"
rules="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/49-smt-control.rules"
audio_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/210-setup-audio-tools.archlinux.yml"
launcher_linux="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/launch-reaper-linux"
launcher_wine="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/launch-reaper-wine"

case "${DOTFILES_TEST_CASE:-}" in
smt-control-syntax)
    sh -n "$helper"
    grep -q 'ExecStart=/usr/local/bin/smt-control off' "$service"
    grep -q 'ExecStop=/usr/local/bin/smt-control on' "$service"
    grep -q 'smt-control.service' "$rules"
    ;;
smt-control-writes-on-and-off)
    sysfs="${DOTFILES_TEST_TMP}/sys"
    control="${sysfs}/devices/system/cpu/smt/control"
    mkdir -p "$(dirname "$control")"
    printf 'on\n' >"$control"
    SMT_CONTROL_SYSFS_ROOT="$sysfs" "$helper" off
    grep -Fxq 'off' "$control"
    SMT_CONTROL_SYSFS_ROOT="$sysfs" "$helper" on
    grep -Fxq 'on' "$control"
    ;;
smt-control-is-on-demand-in-audio-setup)
    grep -q 'src: smt-control.service$' "$audio_tasks"
    grep -q '49-smt-control.rules' "$audio_tasks"
    grep -A6 'ensure smt-control service (on-demand only)' "$audio_tasks" | grep -q 'enabled: false'
    for launcher in "$launcher_linux" "$launcher_wine"; do
        grep -q 'systemctl start smt-control.service' "$launcher"
        grep -q 'systemctl stop smt-control.service' "$launcher"
        grep -q 'smt_boost_start()' "$launcher"
        grep -q 'smt_boost_stop()' "$launcher"
    done
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
