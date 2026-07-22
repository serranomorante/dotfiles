#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio midi shell
# dotfiles-test-case: pedalboard-midi-actions-dispatch

# Purpose: Verify the pedalboard MIDI action mapper parses CC events and matches configured actions.

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-actions"

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
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
