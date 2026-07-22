#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio midi shell
# dotfiles-test-case: pedalboard-midi-actions-dispatch
# dotfiles-test-case: pedalboard-midi-actions-publishes-tft-state
# dotfiles-test-case: pedalboard-midi-actions-service-contract

# Purpose: Verify the pedalboard MIDI action mapper parses CC events and matches configured actions.

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-actions"
unit="${DOTFILES_TEST_ROOT}/audio/dot-config/systemd/user/pedalboard-midi-actions.service"
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
    printf ' 28:0   Control change         15, controller 4, value 64\n'
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

    rg -q '^pedalboard-state desktop 64 0 0$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^pedalboard-state desktop 64 127 0$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q 'match channel=16 cc=80 value=127 edge=press command=echo toggle-mic' "${DOTFILES_TEST_TMP}/state.out"
    ;;
pedalboard-midi-actions-service-contract)
    [[ -s "$unit" ]]
    rg -q '^Description=Pedalboard MIDI desktop action mapper$' "$unit"
    rg -q '^After=graphical-session.target$' "$unit"
    rg -q '^ExecStart=%h/\.local/bin/pedalboard-midi-actions$' "$unit"
    rg -q '^Restart=always$' "$unit"
    rg -q '^RestartSec=5s$' "$unit"
    rg -q '^WantedBy=graphical-session.target$' "$unit"
    rg -q 'Dotfiles: ensure pedalboard MIDI action mapper' "$dotfiles_task"
    rg -q '^    name: pedalboard-midi-actions.service$' "$dotfiles_task"
    rg -q 'Dotfiles: stat pedalboard MIDI action mapper files' "$dotfiles_task"
    rg -q 'audio/dot-local/bin/pedalboard-midi-actions' "$dotfiles_task"
    rg -q 'audio/dot-config/systemd/user/pedalboard-midi-actions.service' "$dotfiles_task"
    rg -q 'audio/dot-config/dotfiles/pedalboard-midi-actions.tsv' "$dotfiles_task"
    rg -q 'Dotfiles: record applied pedalboard MIDI action mapper checksum' "$dotfiles_task"
    rg -q 'pedalboard-midi-actions-sha256' "$dotfiles_task"
    rg -q 'handler_restart_pedalboard_midi_actions_service' "$dotfiles_task"
    rg -q '^- name: handler_restart_pedalboard_midi_actions_service$' "$handlers_file"
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
