#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks plasma dwm keyd systemd session shell fast
# dotfiles-test-case: plasma-dwm-unit-starts-dwm-before-graphical-session
# dotfiles-test-case: plasma-dwm-playbook-masks-kwin-and-enables-dwm
# dotfiles-test-case: plasma-dwm-patched-checkout-is-marker-gated
# dotfiles-test-case: plasma-dwm-autologin-uses-x11-session
# dotfiles-test-case: plasma-dwm-autostart-policy-keeps-plasma-target-loadable
# dotfiles-test-case: plasma-dwm-keyd-observer-follows-plasma-workspace

# Purpose: Guard the Plasma systemd boot contract that lets dwm replace KWin.

systemd_user_dir="${DOTFILES_TEST_ROOT}/systemd/dot-config/systemd/user"
plasma_wm_unit="${systemd_user_dir}/plasma-wm.service"
xdg_target_mask="${systemd_user_dir}/xdg-desktop-autostart.target"
compositor_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/100-setup-compositor.archlinux.yml"
autostart_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/15-setup-xdg-autostart-policy.archlinux.yml"
sddm_autologin="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/sddm/autologin.conf"
keyd_observer_unit="${DOTFILES_TEST_ROOT}/peripherals/dot-config/systemd/user/keyd-observer.service"

assert_file_contains() {
    local file=$1
    local expected=$2

    grep -Fxq "$expected" "$file" || {
        printf 'expected %s to contain exact line: %s\n' "$file" "$expected" >&2
        exit 1
    }
}

task_block() {
    local file=$1
    local name=$2

    awk -v name="$name" '
        /^- name: / {
            if (in_task) {
                exit
            }
            if (index($0, name)) {
                in_task = 1
            }
        }
        in_task {
            print
        }
    ' "$file"
}

assert_task_contains() {
    local file=$1
    local task_name=$2
    local expected=$3
    local block

    block=$(task_block "$file" "$task_name")
    [ -n "$block" ] || {
        printf 'task not found in %s: %s\n' "$file" "$task_name" >&2
        exit 1
    }

    grep -Fq "$expected" <<<"$block" || {
        printf 'expected task "%s" in %s to contain: %s\n' "$task_name" "$file" "$expected" >&2
        printf '%s\n' '--- task block ---' >&2
        printf '%s\n' "$block" >&2
        exit 1
    }
}

case "${DOTFILES_TEST_CASE:-}" in
plasma-dwm-unit-starts-dwm-before-graphical-session)
    assert_file_contains "$plasma_wm_unit" "Description=Plasma Custom Window Manager"
    assert_file_contains "$plasma_wm_unit" "Before=graphical-session.target"
    assert_file_contains "$plasma_wm_unit" "ExecStart=/usr/local/bin/dwm"
    assert_file_contains "$plasma_wm_unit" "Restart=on-failure"
    assert_file_contains "$plasma_wm_unit" "WantedBy=graphical-session.target"
    ;;
plasma-dwm-playbook-masks-kwin-and-enables-dwm)
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: remove packages" "name: kwin"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: remove packages" "state: absent"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: remove packages" "force: true"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure mask kwin service" "name: plasma-kwin_x11.service"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure mask kwin service" "enabled: false"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure mask kwin service" "masked: true"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: kwriteconfig6" "kwriteconfig6 --file startkderc --group General --key systemdBoot true"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure dwm service" "name: plasma-wm.service"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure dwm service" "enabled: true"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: ensure dwm service" "masked: false"
    ;;
plasma-dwm-patched-checkout-is-marker-gated)
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: stat dwm patch marker" ".ansible-dwm-patches-{{ arch_dwm_version | regex_replace('[^A-Za-z0-9_.-]', '_') }}-patch-stack-v1"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: clone latest dwm" "tasks_from: git"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: clone latest dwm" "update_diff_git_force: true"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: clone latest dwm" "when: not var_dwm_patch_marker.stat.exists"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: apply dwm patches" "when: not var_dwm_patch_marker.stat.exists"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: record dwm patch marker" "when: not var_dwm_patch_marker.stat.exists"
    assert_task_contains "$compositor_tasks" "[archlinux] Compositor: install dwm" "not var_dwm_patch_marker.stat.exists or not var_installed_dwm.stat.exists"
    ;;
plasma-dwm-autologin-uses-x11-session)
    assert_file_contains "$sddm_autologin" "Session=plasmax11"
    ;;
plasma-dwm-autostart-policy-keeps-plasma-target-loadable)
    [ ! -e "$xdg_target_mask" ] || {
        printf 'do not ship a user mask for xdg-desktop-autostart.target; Plasma systemd boot wants this target\n' >&2
        exit 1
    }
    assert_task_contains "$autostart_tasks" "[archlinux] XDG autostart policy: mask systemd XDG autostart generator" "dest: /etc/systemd/user-generators/systemd-xdg-autostart-generator"
    assert_task_contains "$autostart_tasks" "[archlinux] XDG autostart policy: mask systemd XDG autostart generator" "src: /dev/null"
    assert_task_contains "$autostart_tasks" "[archlinux] XDG autostart policy: remove stale user target mask" "path: ~/.config/systemd/user/xdg-desktop-autostart.target"
    assert_task_contains "$autostart_tasks" "[archlinux] XDG autostart policy: remove stale user target mask" "state: absent"
    ;;
plasma-dwm-keyd-observer-follows-plasma-workspace)
    assert_file_contains "$keyd_observer_unit" "Description=Keyd observer"
    assert_file_contains "$keyd_observer_unit" "After=plasma-workspace.target"
    assert_file_contains "$keyd_observer_unit" "ExecStart=%h/bin/keyd-observer"
    assert_file_contains "$keyd_observer_unit" "Restart=always"
    assert_file_contains "$keyd_observer_unit" "RestartSec=1"
    assert_file_contains "$keyd_observer_unit" "WantedBy=plasma-workspace.target"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
