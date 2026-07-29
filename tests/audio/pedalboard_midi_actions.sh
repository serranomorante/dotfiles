#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio midi shell
# dotfiles-test-case: pedalboard-midi-actions-dispatch
# dotfiles-test-case: pedalboard-midi-actions-profile-dispatch
# dotfiles-test-case: pedalboard-midi-actions-shift-dispatch
# dotfiles-test-case: pedalboard-midi-actions-publishes-tft-state
# dotfiles-test-case: pedalboard-midi-profile-host-action-profile
# dotfiles-test-case: pedalboard-midi-actions-service-contract

# Purpose: Verify the pedalboard MIDI action mapper parses CC events and matches configured actions.

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-actions"
profile_script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profile"
profiles_file="${DOTFILES_TEST_ROOT}/audio/dot-local/share/dotfiles/pedalboard-midi-profiles.tsv"
profiles_command="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profiles"
export PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file"
export PEDALBOARD_MIDI_PROFILES_COMMAND="$profiles_command"
template_unit="${DOTFILES_TEST_ROOT}/audio/dot-config/systemd/user/pedalboard-midi-actions@.service"
dotfiles_task="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/30-setup-dotfiles.archlinux.yml"
handlers_file="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/handlers/main.yml"

case "${DOTFILES_TEST_CASE:-}" in
pedalboard-midi-actions-dispatch)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    config="${DOTFILES_TEST_TMP}/pedalboard-midi-actions.tsv"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/aseqdump" <<'SH'
#!/bin/sh
case "$1" in
  -l)
    printf ' Port    Client name                      Port name\n'
    printf ' 28:0    Arduino Micro                    Arduino Micro MIDI 1\n'
    ;;
  -p)
    printf 'Waiting for data. Press Ctrl+C to end.\n'
    printf 'Source  Event                  Ch  Data\n'
    printf ' 28:0   Control change         15, controller 80, value 127\n'
    printf ' 28:0   Control change         15, controller 80, value 0\n'
    ;;
esac
SH
    chmod +x "${fake_bin}/aseqdump"

    printf '16 80 press echo toggle-mic\n' >"$config"
    PATH="${fake_bin}:$PATH" "$script" --config "$config" --dry-run >"${DOTFILES_TEST_TMP}/actions.out" 2>"${DOTFILES_TEST_TMP}/actions.err"

    rg -q 'match channel=16 cc=80 value=127 edge=press command=echo toggle-mic' "${DOTFILES_TEST_TMP}/actions.out"
    refute rg -q 'value=0 edge=release' "${DOTFILES_TEST_TMP}/actions.out"
    ;;
pedalboard-midi-actions-profile-dispatch)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    config_dir="${DOTFILES_TEST_TMP}/config/dotfiles"
    mkdir -p "$fake_bin" "$config_dir"

    cat >"${fake_bin}/aseqdump" <<'SH'
#!/bin/sh
case "$1" in
  -l)
    printf ' Port    Client name                      Port name\n'
    printf ' 28:0    Arduino Micro                    Arduino Micro MIDI 1\n'
    ;;
  -p)
    printf 'Waiting for data. Press Ctrl+C to end.\n'
    printf 'Source  Event                  Ch  Data\n'
    printf ' 28:0   Control change         14, controller 80, value 127\n'
    ;;
esac
SH
    chmod +x "${fake_bin}/aseqdump"

    printf '15 80 press echo obs-toggle\n' >"${config_dir}/pedalboard-midi-actions.obs-mouseless-setup.tsv"
    XDG_CONFIG_HOME="${DOTFILES_TEST_TMP}/config" \
      PATH="${fake_bin}:$PATH" \
      "$script" --profile obs-mouseless-setup --dry-run >"${DOTFILES_TEST_TMP}/profile-actions.out" 2>"${DOTFILES_TEST_TMP}/profile-actions.err"

    rg -q 'match channel=15 cc=80 value=127 edge=press command=echo obs-toggle' "${DOTFILES_TEST_TMP}/profile-actions.out"
    ;;
pedalboard-midi-actions-shift-dispatch)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    config="${DOTFILES_TEST_TMP}/pedalboard-midi-actions.tsv"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/aseqdump" <<'SH'
#!/bin/sh
case "$1" in
  -l)
    printf ' Port    Client name                      Port name\n'
    printf ' 28:0    Arduino Micro                    Arduino Micro MIDI 1\n'
    ;;
  -p)
    printf 'Waiting for data. Press Ctrl+C to end.\n'
    printf 'Source  Event                  Ch  Data\n'
    printf ' 28:0   Control change         15, controller 4, value 20\n'
    printf ' 28:0   Control change         15, controller 4, value 18\n'
    printf ' 28:0   Control change         15, controller 80, value 127\n'
    printf ' 28:0   Control change         15, controller 4, value 21\n'
    printf ' 28:0   Control change         15, controller 4, value 23\n'
    printf ' 28:0   Control change         15, controller 81, value 127\n'
    printf ' 28:0   Control change         15, controller 4, value 20\n'
    ;;
esac
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$PEDALBOARD_TEST_DESKTOP_EVENT_LOG"
SH
    chmod +x "${fake_bin}/aseqdump" "${fake_bin}/desktop-action-event"

    {
      printf '16 80 press echo mic-toggle\n'
      printf '16 81 press echo screenshot\n'
      printf '16 80 shift-press echo record-toggle\n'
      printf '16 81 shift-press echo monitor-toggle\n'
    } >"$config"

    PEDALBOARD_TEST_DESKTOP_EVENT_LOG="${DOTFILES_TEST_TMP}/desktop-events.log" \
      PATH="${fake_bin}:$PATH" "$script" --config "$config" --dry-run >"${DOTFILES_TEST_TMP}/shift-actions.out" 2>"${DOTFILES_TEST_TMP}/shift-actions.err"

    rg -q 'match channel=16 cc=80 value=127 edge=press command=echo mic-toggle' "${DOTFILES_TEST_TMP}/shift-actions.out"
    rg -q 'match channel=16 cc=81 value=127 edge=shift-press command=echo monitor-toggle' "${DOTFILES_TEST_TMP}/shift-actions.out"
    refute rg -q 'command=echo record-toggle' "${DOTFILES_TEST_TMP}/shift-actions.out"
    refute rg -q 'command=echo screenshot' "${DOTFILES_TEST_TMP}/shift-actions.out"
    rg -q '^desktop.layer BASE$' "${DOTFILES_TEST_TMP}/desktop-events.log"
    rg -q '^desktop.layer SHIFT$' "${DOTFILES_TEST_TMP}/desktop-events.log"
    [[ $(rg -c '^desktop.layer BASE$' "${DOTFILES_TEST_TMP}/desktop-events.log") -eq 2 ]]
    [[ $(rg -c '^desktop.layer SHIFT$' "${DOTFILES_TEST_TMP}/desktop-events.log") -eq 1 ]]
    ;;
pedalboard-midi-actions-publishes-tft-state)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    config="${DOTFILES_TEST_TMP}/pedalboard-midi-actions.tsv"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/aseqdump" <<'SH'
#!/bin/sh
case "$1" in
  -l)
    printf ' Port    Client name                      Port name\n'
    printf ' 28:0    Arduino Micro                    Arduino Micro MIDI 1\n'
    ;;
  -p)
    printf 'Waiting for data. Press Ctrl+C to end.\n'
    printf 'Source  Event                  Ch  Data\n'
    printf ' 28:0   Control change         15, controller 4, value 20\n'
    printf ' 28:0   Control change         15, controller 80, value 127\n'
    printf ' 28:0   Control change         15, controller 81, value 0\n'
    ;;
esac
SH
    cat >"${fake_bin}/keyboard-midi-controller" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$PEDALBOARD_TEST_FEEDBACK_LOG"
SH
    chmod +x "${fake_bin}/aseqdump" "${fake_bin}/keyboard-midi-controller"

    printf '16 80 press echo toggle-mic\n' >"$config"
    PEDALBOARD_TEST_FEEDBACK_LOG="${DOTFILES_TEST_TMP}/feedback.log" \
      PEDALBOARD_MIDI_FEEDBACK_COMMAND="${fake_bin}/keyboard-midi-controller" \
      PATH="${fake_bin}:$PATH" "$script" --config "$config" --dry-run >"${DOTFILES_TEST_TMP}/state.out" 2>"${DOTFILES_TEST_TMP}/state.err"

    rg -q '^pedalboard-state desktop 20 0 0$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^pedalboard-state desktop 20 127 0$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q 'match channel=16 cc=80 value=127 edge=press command=echo toggle-mic' "${DOTFILES_TEST_TMP}/state.out"
    ;;
pedalboard-midi-profile-host-action-profile)
    "$profile_script" --dry-run obs-mouseless-setup >"${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^serial profile obs-mouseless-setup$' "${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@desktop.service$' "${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@obs-mouseless-setup.service$' "${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^systemctl --user start pedalboard-midi-actions@obs-mouseless-setup.service$' "${DOTFILES_TEST_TMP}/obs-profile.out"

    "$profile_script" --dry-run desktop >"${DOTFILES_TEST_TMP}/desktop-profile.out"
    rg -q '^serial profile desktop$' "${DOTFILES_TEST_TMP}/desktop-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@desktop.service$' "${DOTFILES_TEST_TMP}/desktop-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@obs-mouseless-setup.service$' "${DOTFILES_TEST_TMP}/desktop-profile.out"
    rg -q '^systemctl --user start pedalboard-midi-actions@desktop.service$' "${DOTFILES_TEST_TMP}/desktop-profile.out"

    "$profile_script" --dry-run piano >"${DOTFILES_TEST_TMP}/piano-profile.out"
    rg -q '^serial profile piano$' "${DOTFILES_TEST_TMP}/piano-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@desktop.service$' "${DOTFILES_TEST_TMP}/piano-profile.out"
    rg -q '^systemctl --user stop pedalboard-midi-actions@obs-mouseless-setup.service$' "${DOTFILES_TEST_TMP}/piano-profile.out"
    refute rg -q '^systemctl --user start ' "${DOTFILES_TEST_TMP}/piano-profile.out"
    ;;
pedalboard-midi-actions-service-contract)
    [[ -s "$template_unit" ]]
    rg -q '^ExecStart=%h/\.local/bin/pedalboard-midi-actions --profile %i$' "$template_unit"
    refute rg -q '^Conflicts=' "$template_unit"
    rg -q '^EnvironmentFile=-%h/.config/dotfiles/pedalboard-midi-actions.%i.env$' "$template_unit"
    rg -q 'Dotfiles: stat pedalboard MIDI action mapper files' "$dotfiles_task"
    rg -q 'audio/dot-local/bin/pedalboard-midi-actions' "$dotfiles_task"
    rg -q '^last_desktop_layer=$' "$script"
    rg -q '\[ "\$next_layer" != "\$last_desktop_layer" \] \|\| return 0' "$script"
    rg -q '^reconnect_delay=\$\{PEDALBOARD_MIDI_RECONNECT_DELAY:-2\}$' "$script"
    rg -q 'validate_reconnect_delay' "$script"
    rg -q 'handle_aseqdump_line' "$script"
    rg -q -- '--profile PROFILE' "$script"
    rg -q 'PEDALBOARD_MIDI_ACTIONS_PROFILE' "$script"
    rg -q 'listen_port' "$script"
    rg -q 'run_listener_loop' "$script"
    rg -q 'wait_for_port_visibility_change' "$script"
    rg -q 'pedalboard port visibility changed' "$script"
    refute rg -q 'wait_for_midi_topology_change' "$script"
    refute rg -q 'aseqdump -p 0:1' "$script"
    refute rg -q 'System Announce' "$script"
    refute rg -q 'udevadm monitor' "$script"
    rg -q 'MIDI port visibility changed; reconnecting pedalboard listener' "$script"
    rg -q 'wait -n "\$listener_pid" "\$watchdog_pid"' "$script"
    rg -q 'pgrep -P "\$pid"' "$script"
    rg -q 'stop_background_pid "\$child"' "$script"
    rg -q '\[ "\$port_locked" -eq 1 \] \|\| port=' "$script"
    rg -q 'audio/dot-local/bin/pedalboard-midi-profile' "$dotfiles_task"
    rg -q 'audio/dot-local/bin/pedalboard-midi-profiles' "$dotfiles_task"
    rg -q 'audio/dot-local/bin/pedalboard-midi-profile-picker' "$dotfiles_task"
    rg -q 'audio/dot-local/share/dotfiles/pedalboard-midi-profiles.tsv' "$dotfiles_task"
    rg -q 'audio/dot-config/systemd/user/pedalboard-midi-actions@.service' "$dotfiles_task"
    rg -q 'audio/dot-config/dotfiles/pedalboard-midi-actions.desktop.tsv' "$dotfiles_task"
    rg -q 'audio/dot-config/dotfiles/pedalboard-midi-actions.obs-mouseless-setup.tsv' "$dotfiles_task"
    rg -q 'Dotfiles: record applied pedalboard MIDI action mapper checksum' "$dotfiles_task"
    rg -q 'pedalboard-midi-actions-sha256' "$dotfiles_task"
    rg -q 'handler_restart_pedalboard_midi_actions_service' "$dotfiles_task"
    rg -q '^- name: handler_restart_pedalboard_midi_actions_service$' "$handlers_file"
    bash -n "$profile_script"
    bash -n "${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profiles"
    sh -n "${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profile-picker"
    rg -q 'profile piano' "$profile_script"
    rg -q 'profile guitar' "$profile_script"
    rg -q 'profile desktop' "$profile_script"
    rg -q 'obs-mouseless-setup' "$profile_script"
    rg -q 'activate_action_profile' "$profile_script"
    refute rg -q 'enable --now|disable --now' "$profile_script"
    rg -q -- '--dry-run' "$profile_script"
    rg -q 'range ZERO FULL' "$profile_script"
    rg -q 'range reset' "$profile_script"
    rg -q 'run_serial_command "range reset"' "$profile_script"
    rg -q 'run_serial_command "range \$range_zero \$range_full"' "$profile_script"
    rg -q 'keyboard-midi-controller' "$profile_script"
    rg -q 'pedalboard-state "\$profile" "\$value" 0 0' "$profile_script"
    rg -q '^16 80 press desktop-action-run mic-toggle$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.desktop.tsv"
    rg -q '^16 81 press desktop-action-run screenshot$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.desktop.tsv"
    rg -q '^16 80 shift-press desktop-action-run record-toggle$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.desktop.tsv"
    rg -q '^16 81 shift-press desktop-action-run monitor-toggle$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.desktop.tsv"
    rg -q '^15 4 any teleprompter-scroll$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.obs-mouseless-setup.tsv"
    rg -q '^15 80 press desktop-action-run obs-scene-toggle$' "${DOTFILES_TEST_ROOT}/audio/dot-config/dotfiles/pedalboard-midi-actions.obs-mouseless-setup.tsv"
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
