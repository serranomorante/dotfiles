#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: peripherals
# dotfiles-test-tags: peripherals keyboard midi go shell systemd keyd
# dotfiles-test-readonly: /home/aaaa/data/repos/keyd
# dotfiles-test-case: keyboard-midi-controller-go-tests
# dotfiles-test-case: keyboard-midi-controller-wrapper-syntax
# dotfiles-test-case: keyboard-midi-controller-wrapper-compile-cache
# dotfiles-test-case: mode-osd-wrapper-compile-cache
# dotfiles-test-case: keyboard-midi-controller-keyd-template-check
# dotfiles-test-case: keyboard-midi-controller-dotfiles-contract

# Purpose: Verify the HHKB MIDI controller daemon and its dotfiles integration.

source_dir="${DOTFILES_TEST_ROOT}/peripherals/dot-local/share/dotfiles/keyboard-midi-controller"
go_test_file="${DOTFILES_TEST_ROOT}/tests/peripherals/keyboard_midi_controller_main_test.go"
wrapper="${DOTFILES_TEST_ROOT}/peripherals/bin/keyboard-midi-controller"
mode_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/mode-osd"
show_keyboard_midi_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/show_keyboard_midi_osd"
hide_keyboard_midi_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/hide_keyboard_midi_osd"
show_mouseless_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/show_mouseless_osd.sh"
hide_mouseless_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/hide_mouseless_osd.sh"
show_readline_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/show_readline_osd.sh"
hide_readline_osd="${DOTFILES_TEST_ROOT}/peripherals/bin/hide_readline_osd.sh"
keyd_template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/keyd-default.conf"
keyd_max_layers_patch="${DOTFILES_TEST_ROOT}/assets/patches/keyd/increase-max-layers-for-midi.patch"
keyboard_task="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/40-setup-keyboard-tools.archlinux.yml"
embedded_task="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/200-setup-embedded-tools.archlinux.yml"
dotfiles_task="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/30-setup-dotfiles.archlinux.yml"
sws_task="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/wine-tools/sws-extensions.task.yml"
wine_reaper_firejail_template="${DOTFILES_TEST_ROOT}/for-my-eyes-only/playbooks/roles/60-for-my-eyes-only/templates/wine-reaper.local"
handlers_file="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/handlers/main.yml"
unit_file="${DOTFILES_TEST_ROOT}/peripherals/dot-config/systemd/user/keyboard-midi-controller.service"
mode_osd_unit="${DOTFILES_TEST_ROOT}/peripherals/dot-config/systemd/user/mode-osd.service"
led_firmware="${DOTFILES_TEST_ROOT}/assets/firmware/keyboard-midi-led-matrix/keyboard-midi-led-matrix.ino"
tft_firmware="${DOTFILES_TEST_ROOT}/assets/firmware/keyboard-midi-tft-display/keyboard-midi-tft-display.ino"
reaper_startup_script="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/__startup.lua"
midi_editor_state_feedback="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/midi_editor_state_feedback.lua"
item_state_feedback="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/item_state_feedback.lua"
project_transport_state_feedback="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/project_transport_state_feedback.lua"
readline_notify_service="${DOTFILES_TEST_ROOT}/assets/services/readline-mode-notify.service"
readline_notify_watcher="${DOTFILES_TEST_ROOT}/assets/scripts/keyd/readline-mode-watcher.sh"
cursor_indicator_unit="${DOTFILES_TEST_ROOT}/peripherals/dot-config/systemd/user/cursor_indicator@.service"
cursor_indicator_source_dir="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/cursor_indicator"
cursor_indicator_source="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/cursor_indicator/cursor_indicator.c"
keyd_observer="${DOTFILES_TEST_ROOT}/peripherals/bin/keyd-observer"
peripherals_vars="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/defaults/main/peripherals.vars.yml"
dunst_config="${DOTFILES_TEST_ROOT}/dunst/dot-config/dunst/dunstrc"

require_go() {
    command -v go >/dev/null 2>&1 || {
        printf 'go is not available\n' >&2
        exit 77
    }
}

keyd_check_binary() {
    keyd_source="${DOTFILES_TEST_KEYD_SOURCE:-$(dirname "$DOTFILES_TEST_ROOT")/data/repos/keyd}"
    if [[ -f "${keyd_source}/Makefile" && -f "${keyd_source}/src/config.h" ]]; then
        keyd_build="${DOTFILES_TEST_TMP}/keyd-src"
        cp -a "$keyd_source" "$keyd_build"
        if ! rg -q '#define MAX_LAYERS[[:space:]]+128' "${keyd_build}/src/config.h" || ! rg -q '#define MAX_SECTIONS 128' "${keyd_build}/src/ini.h"; then
            patch -d "$keyd_build" -p1 <"$keyd_max_layers_patch" >/dev/null
        fi
        make -C "$keyd_build" all >/dev/null
        printf '%s\n' "${keyd_build}/bin/keyd"
        return
    fi

    command -v keyd >/dev/null 2>&1 || {
        printf 'keyd is not available and %s is missing\n' "$keyd_source" >&2
        exit 77
    }
    command -v keyd
}

run_go_test() {
    require_go
    mkdir -p "${DOTFILES_TEST_TMP}/gocache" "${DOTFILES_TEST_TMP}/gotmp"
    test_source="${DOTFILES_TEST_TMP}/go-source"
    cp -a "$source_dir" "$test_source"
    cp "$go_test_file" "${test_source}/main_test.go"
    (
        cd "$test_source"
        GOWORK=off GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" go test ./...
    )
}

case "${DOTFILES_TEST_CASE:-}" in
keyboard-midi-controller-go-tests)
    run_go_test
    ;;
keyboard-midi-controller-wrapper-syntax)
    sh -n "$wrapper"
    sh -n "$mode_osd"
    sh -n "$keyd_observer"
    sh -n "$show_keyboard_midi_osd"
    sh -n "$hide_keyboard_midi_osd"
    sh -n "$show_mouseless_osd"
    sh -n "$hide_mouseless_osd"
    sh -n "$show_readline_osd"
    sh -n "$hide_readline_osd"
    ;;
keyboard-midi-controller-wrapper-compile-cache)
    require_go
    home="${DOTFILES_TEST_TMP}/home"
    cache="${DOTFILES_TEST_TMP}/cache"
    test_source="${DOTFILES_TEST_TMP}/source"
    mkdir -p "$home" "$cache" "${DOTFILES_TEST_TMP}/gocache" "${DOTFILES_TEST_TMP}/gotmp"
    cp -a "$source_dir" "$test_source"

    HOME="$home" XDG_CACHE_HOME="$cache" GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" DOTFILES_KEYBOARD_MIDI_CONTROLLER_SOURCE_DIR="$test_source" "$wrapper" --compile-cache >"${DOTFILES_TEST_TMP}/compile-1.out"
    HOME="$home" XDG_CACHE_HOME="$cache" GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" DOTFILES_KEYBOARD_MIDI_CONTROLLER_SOURCE_DIR="$test_source" "$wrapper" --compile-cache >"${DOTFILES_TEST_TMP}/compile-2.out"
    printf '%s\n' 'package main' 'func TestHashIgnoredByRuntimeBuild(t *testing.T) {}' >"${test_source}/hash_ignored_test.go"
    HOME="$home" XDG_CACHE_HOME="$cache" GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" DOTFILES_KEYBOARD_MIDI_CONTROLLER_SOURCE_DIR="$test_source" "$wrapper" --compile-cache >"${DOTFILES_TEST_TMP}/compile-test-only.out"

    rg -q '^compiled$' "${DOTFILES_TEST_TMP}/compile-1.out"
    [[ ! -s "${DOTFILES_TEST_TMP}/compile-2.out" ]]
    [[ ! -s "${DOTFILES_TEST_TMP}/compile-test-only.out" ]]
    [[ -x "${cache}/dotfiles/keyboard-midi-controller/keyboard-midi-controller" ]]
    [[ -s "${cache}/dotfiles/keyboard-midi-controller/source.sha256" ]]
    ;;
mode-osd-wrapper-compile-cache)
    command -v cc >/dev/null 2>&1 || {
        printf 'cc is not available\n' >&2
        exit 77
    }
    home="${DOTFILES_TEST_TMP}/home"
    cache="${DOTFILES_TEST_TMP}/cache"
    mkdir -p "$home" "$cache"

    HOME="$home" XDG_CACHE_HOME="$cache" "$mode_osd" --compile-cache >"${DOTFILES_TEST_TMP}/mode-osd-compile-1.out"
    HOME="$home" XDG_CACHE_HOME="$cache" "$mode_osd" --compile-cache >"${DOTFILES_TEST_TMP}/mode-osd-compile-2.out"

    rg -q '^compiled$' "${DOTFILES_TEST_TMP}/mode-osd-compile-1.out"
    rg -q '^unchanged$' "${DOTFILES_TEST_TMP}/mode-osd-compile-2.out"
    [[ -x "${cache}/mode-osd/mode-osd-x11" ]]
    [[ -s "${cache}/mode-osd/mode-osd-x11.c" ]]
    ;;
keyboard-midi-controller-keyd-template-check)
    command -v ansible >/dev/null 2>&1 || {
        printf 'ansible is not available\n' >&2
        exit 77
    }
    rendered="${DOTFILES_TEST_TMP}/keyd-default.conf"
    keyd_binary="$(keyd_check_binary)"
    ansible localhost -m ansible.builtin.template -a "src=${keyd_template} dest=${rendered} mode=0644" -e "@${peripherals_vars}" -e '{"ansible_user_uid":1000,"ansible_facts":{"env":{"USER":"aaaa","HOME":"/home/aaaa"}}}' >/dev/null
    "$keyd_binary" check "$rendered"
    ;;
keyboard-midi-controller-dotfiles-contract)
    ! rg -q '^\[signal_toggle_keyboard_midi_controller\]$' "$keyd_template"
    rg -q '^m = toggle\(midi\)$' "$keyd_template"
    rg -q '^esc = toggle\(midi\)$' "$keyd_template"
    rg -q '^\[midi\]$' "$keyd_template"
    rg -q '^1 = layer\(midi_enc_01\)$' "$keyd_template"
    rg -q '^i = layer\(midi_enc_16\)$' "$keyd_template"
    rg -q '^a = layer\(midi_pad_01\)$' "$keyd_template"
    rg -q '^, = layer\(midi_pad_16\)$' "$keyd_template"
    rg -q '^9 = noop$' "$keyd_template"
    rg -q '^0 = noop$' "$keyd_template"
    rg -q '^o = layer\(midi_channel_select\)$' "$keyd_template"
    rg -q '^p = layer\(midi_bank_select\)$' "$keyd_template"
    rg -q '^\[midi\+tab_as_modifier\]$' "$keyd_template"
    rg -q '^\[midi\+midi_channel_select\]$' "$keyd_template"
    rg -q '^\[midi\+midi_bank_select\]$' "$keyd_template"
    rg -q '^q = layer\(midi_enc_09\)$' "$keyd_template"
    rg -q '^u = layer\(midi_enc_15\)$' "$keyd_template"
    rg -q '^i = layer\(midi_enc_16\)$' "$keyd_template"
    rg -q '^f = layer\(midi_pad_04\)$' "$keyd_template"
    rg -q '^space = layer\(midi_transport_toggle\)$' "$keyd_template"
    rg -q '^; = layer\(midi_transport_continue\)$' "$keyd_template"
    rg -q '^/ = layer\(midi_panic\)$' "$keyd_template"
    rg -q '^\[midi_enc_16\]$' "$keyd_template"
    rg -q '^\[midi_pad_16\]$' "$keyd_template"
    ! rg -q '^9 = layer\(midi_bank_down\)$' "$keyd_template"
    ! rg -q '^0 = layer\(midi_bank_up\)$' "$keyd_template"
    ! rg -q '^o = layer\(midi_channel_down\)$' "$keyd_template"
    ! rg -q '^p = layer\(midi_channel_up\)$' "$keyd_template"
    ! rg -q '^0 = layer\(midi_enc_10\)$' "$keyd_template"
    rg -q '^\[midi_panic\]$' "$keyd_template"
    rg -q '^space = layer\(signal_enter_mouseless_mode\)$' "$keyd_template"
    rg -q '^space = togglem\(midi, macro\(leftcontrol\+rightcontrol\)\)$' "$keyd_template"
    rg -q '^i = toggle\(readline\)$' "$keyd_template"
    ! rg -q '^m = layer\(signal_toggle_keyboard_midi_controller\)$' "$keyd_template"
    ! rg -q '^m = command\(.*/bin/keyboard-midi-controller toggle\)$' "$keyd_template"
    ! rg -q '^\[signal_open_kitty\]$' "$keyd_template"
    rg -q '^enter = command\(/usr/local/bin/run_as_user -u \{\{ ansible_facts\.env\.USER \}\} systemd-run --user \{\{ ansible_facts\.env\.HOME \}\}/bin/kitty\)$' "$keyd_template"

    rg -q 'showMIDIOSDCommand = "show_keyboard_midi_osd"' "${source_dir}/main.go"
    rg -q 'hideMIDIOSDCommand = "hide_keyboard_midi_osd"' "${source_dir}/main.go"
    rg -q 'setMIDIModeNotification' "${source_dir}/main.go"
    rg -q 'keydListenCommand = "keyd"' "${source_dir}/main.go"
    rg -q 'ledClientName\s*=\s*"Keyboard MIDI Controller LED"' "${source_dir}/main.go"
    rg -q 'ledPortName\s*=\s*"LED Out"' "${source_dir}/main.go"
    rg -q 'feedbackClientName\s*=\s*"Keyboard MIDI Controller Feedback"' "${source_dir}/main.go"
    rg -q 'feedbackPortName\s*=\s*"Feedback In"' "${source_dir}/main.go"
    rg -q 'arduinoLEDClientName\s*=\s*"Arduino Micro"' "${source_dir}/main.go"
    rg -q 'arduinoLEDPortName\s*=\s*"Arduino Micro MIDI 1"' "${source_dir}/main.go"
    rg -q 'tftSerialPortEnv\s*=\s*"KMC_TFT_SERIAL_PORT"' "${source_dir}/main.go"
    rg -q 'runLEDAutoConnectLoop' "${source_dir}/main.go"
    rg -q 'newSerialTFTOutput' "${source_dir}/main.go"
    rg -q 'discoverTFTSerialPort' "${source_dir}/main.go"
    rg -q 'setPad\(channel, note, velocity int\)' "${source_dir}/main.go"
    rg -q 'setCC\(channel, controller, value int\)' "${source_dir}/main.go"
    rg -q 'if channel == 9 \{' "${source_dir}/main.go"
    rg -q 'noteInBank == 0 \|\| noteInBank == 1 \|\| noteInBank == 7 \|\| noteInBank >= 8' "${source_dir}/main.go"
    rg -q 'if channel == 10 \{' "${source_dir}/main.go"
    rg -q 'return noteInBank <= 13' "${source_dir}/main.go"
    rg -q 'if channel == 11 \{' "${source_dir}/main.go"
    rg -q 'noteInBank <= 3 \|\| noteInBank == 5 \|\| noteInBank == 6 \|\| noteInBank >= 8' "${source_dir}/main.go"
    rg -q '"K %d %d %d"' "${source_dir}/main.go"
    rg -q '/dev/serial/by-id/\*' "${source_dir}/main.go"
    rg -q 'kmc_connect_to_named_port' "${source_dir}/main.go"
    rg -q 'runKeydListenLoop' "${source_dir}/main.go"
    rg -q 'runFeedbackLoop' "${source_dir}/main.go"
    rg -q 'handleFeedbackEvent' "${source_dir}/main.go"
    rg -q 'feedback-note CH NOTE VEL' "${source_dir}/main.go"
    rg -q 'feedback-cc CH CC VALUE' "${source_dir}/main.go"
    rg -q 'parseExternalFeedbackTriple' "${source_dir}/main.go"
    rg -q 'applyFeedbackNote' "${source_dir}/main.go"
    rg -q 'applyFeedbackCC' "${source_dir}/main.go"
    rg -q 'feedback-note CH NOTE VEL' "$wrapper"
    rg -q 'feedback-cc CH CC VALUE' "$wrapper"
    rg -q 'matrix clears delays the realtime play/stop LED feedback' "${source_dir}/main.go"
    rg -q 'openFeedbackMIDI' "${source_dir}/main.go"
    rg -q 'waitForLEDMIDI' "${source_dir}/main.go"
    rg -q 'consumeKeydListen' "${source_dir}/main.go"
    rg -q 'handleKeydLayerEvent' "${source_dir}/main.go"
    rg -q 'encoderRepeatDelay' "${source_dir}/main.go"
    rg -q '#cgo pkg-config: jack' "${source_dir}/main.go"
    rg -q 'SND_SEQ_PORT_TYPE_HARDWARE' "${source_dir}/main.go"
    rg -q 'SND_SEQ_PORT_TYPE_PORT' "${source_dir}/main.go"
    ! rg -q 'SND_SEQ_PORT_TYPE_APPLICATION' "${source_dir}/main.go"
    rg -q 'openJACKMIDI' "${source_dir}/main.go"
    rg -q 'JackPortIsOutput' "${source_dir}/main.go"
    rg -q 'JackPortIsPhysical' "${source_dir}/main.go"
    rg -q 'JackPortIsTerminal' "${source_dir}/main.go"
    rg -q 'JACK_DEFAULT_MIDI_TYPE' "${source_dir}/main.go"
    rg -q 'jack_midi_event_reserve' "${source_dir}/main.go"
    rg -q '"led_client":\s*ledClientName' "${source_dir}/main.go"
    rg -q '"feedback_client":\s*feedbackClientName' "${source_dir}/main.go"
    rg -q '"outputs":\s*d\.outputNames\(\)' "${source_dir}/main.go"
    rg -q 'releaseHeldNotes' "${source_dir}/main.go"
    ! rg -q 'exclusiveInputGrab|eviocgrab|EVIOCGRAB|targetInputName|ioctlGrab|keyd virtual keyboard|handleInputEvent|inputDevice|inputEvent' "${source_dir}/main.go"
    ! rg -q 'cursor_indicator|midiIndicatorColor' "${source_dir}/main.go"
    ! rg -q 'leaveMouselessMode' "${source_dir}/main.go"

    rg -q 'MAX_LAYERS\s+128' "$keyd_max_layers_patch"
    rg -q 'MAX_SECTIONS 128' "$keyd_max_layers_patch"
    rg -q 'keyboard-midi-controller dependencies' "$keyboard_task"
    rg -q '      - alsa-lib$' "$keyboard_task"
    rg -q '      - pipewire-jack$' "$keyboard_task"
    rg -q 'increase-max-layers-for-midi.patch' "$keyboard_task"
    rg -q 'keyd-build-midi-layers-v1' "$keyboard_task"
    rg -q '    - keyboard-midi-controller.service$' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: compile keyboard MIDI controller"' "$keyboard_task"
    rg -q '      - "\{\{ ansible_facts\.env\.HOME \}\}/bin/keyboard-midi-controller"$' "$keyboard_task"
    rg -q '      - --compile-cache$' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: check running keyboard MIDI controller cache"' "$keyboard_task"
    rg -q 'systemctl --user show keyboard-midi-controller.service --property=MainPID --value' "$keyboard_task"
    rg -q '/proc/\$pid/exe' "$keyboard_task"
    rg -q "stat -Lc '%d:%i'" "$keyboard_task"
    rg -q 'var_keyboard_midi_controller_running_cache' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: restart keyboard MIDI controller after cache refresh"' "$keyboard_task"
    rg -q '^    name: keyboard-midi-controller.service$' "$keyboard_task"
    rg -q '^    state: restarted$' "$keyboard_task"
    rg -q '^  when: var_keyboard_midi_controller_compile_cache.changed or var_keyboard_midi_controller_running_cache.changed$' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: stop retired cursor indicator services"' "$keyboard_task"
    rg -q 'cursor_indicator@red.service' "$keyboard_task"
    rg -q 'cursor_indicator@blue.service' "$keyboard_task"
    rg -q 'cursor_indicator@green.service' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: remove retired cursor indicator files"' "$keyboard_task"
    rg -q '~/.config/systemd/user/cursor_indicator@.service' "$keyboard_task"
    rg -q '~/bin/cursor_indicator' "$keyboard_task"
    rg -q '~/data/repos/cursor_indicator' "$keyboard_task"
    rg -q 'handler_reload_user_systemd' "$keyboard_task"
    ! rg -q 'clone cursor indicator|make cursor indicator|symlink cursor indicator' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: stat keyd observer script"' "$keyboard_task"
    rg -q 'path: ~/dotfiles/peripherals/bin/keyd-observer' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: record applied keyd observer checksum"' "$keyboard_task"
    rg -q 'dest: ~/.local/state/dotfiles/keyd-observer.sha256' "$keyboard_task"
    rg -q 'handler_restart_keyd_observer_service' "$keyboard_task"
    rg -q '"\[archlinux\] Keyboard peripheral: prepare readline-mode-notify script"' "$keyboard_task"
    rg -q 'handler_reset_failed_readline_mode_notify_service' "$keyboard_task"
    rg -q 'handler_ensure_readline_mode_notify_service' "$keyboard_task"
    ! rg -q 'Dotfiles: record applied keyd observer checksum' "$dotfiles_task"

    rg -q '^- name: handler_restart_keyd_observer_service$' "$handlers_file"
    rg -q '^    name: keyd-observer.service$' "$handlers_file"
    rg -q '^- name: handler_restart_keyd$' "$handlers_file"
    awk '/^- name: handler_restart_keyd$/{in_handler=1} in_handler{print} in_handler && /^$/{exit}' "$handlers_file" >"${DOTFILES_TEST_TMP}/keyd-restart-handler"
    rg -q '^  ansible.builtin.systemd_service:$' "${DOTFILES_TEST_TMP}/keyd-restart-handler"
    rg -q '^    name: keyd.service$' "${DOTFILES_TEST_TMP}/keyd-restart-handler"
    rg -q '^    state: restarted$' "${DOTFILES_TEST_TMP}/keyd-restart-handler"
    ! rg -q 'keyd reload|handler_restart_keyd_result' "${DOTFILES_TEST_TMP}/keyd-restart-handler"
    rg -q '^- name: handler_restart_keyboard_midi_controller_service$' "$handlers_file"
    rg -q '^    name: keyboard-midi-controller.service$' "$handlers_file"
    rg -q '^- name: handler_reset_failed_readline_mode_notify_service$' "$handlers_file"
    awk '/^- name: handler_reset_failed_readline_mode_notify_service$/{in_handler=1} in_handler{print} in_handler && /^$/{exit}' "$handlers_file" >"${DOTFILES_TEST_TMP}/readline-reset-failed-handler"
    rg -q '^      - reset-failed$' "${DOTFILES_TEST_TMP}/readline-reset-failed-handler"
    rg -q '^      - readline-mode-notify.service$' "${DOTFILES_TEST_TMP}/readline-reset-failed-handler"
    rg -q '^- name: handler_ensure_readline_mode_notify_service$' "$handlers_file"
    rg -q '^    name: readline-mode-notify.service$' "$handlers_file"
    rg -q '^- name: handler_enable_start_keyd_application_mapper_service$' "$handlers_file"
    awk '/^- name: handler_enable_start_keyd_application_mapper_service$/{in_handler=1} in_handler{print} in_handler && /^$/{exit}' "$handlers_file" >"${DOTFILES_TEST_TMP}/keyd-application-mapper-handler"
    rg -q '^    name: keyd-application-mapper.service$' "${DOTFILES_TEST_TMP}/keyd-application-mapper-handler"
    rg -q '^    enabled: false$' "${DOTFILES_TEST_TMP}/keyd-application-mapper-handler"
    rg -q '^    state: restarted$' "$handlers_file"
    rg -q '^    daemon_reload: true$' "$handlers_file"

    rg -q '^Description=Keyboard MIDI controller daemon$' "$unit_file"
    rg -q '^ExecStart=%h/bin/keyboard-midi-controller run$' "$unit_file"
    rg -q '^Restart=on-failure$' "$unit_file"
    rg -q '^WantedBy=graphical-session.target$' "$unit_file"
    [[ -s "$led_firmware" ]]
    rg -q '^#include <Adafruit_NeoPixel.h>$' "$led_firmware"
    rg -q '^#include "MIDIUSB.h"$' "$led_firmware"
    rg -q '^const uint8_t NOTE_BASE = 36;$' "$led_firmware"
    rg -q 'data1 == 120 \|\| data1 == 121 \|\| data1 == 123' "$led_firmware"
    [[ -s "$tft_firmware" ]]
    rg -q '^#include <Adafruit_GFX.h>$' "$tft_firmware"
    rg -q '^#include <Adafruit_ILI9341.h>$' "$tft_firmware"
    rg -q '^const uint8_t TFT_CS = 10;$' "$tft_firmware"
    rg -q '^const uint8_t TFT_DC = 9;$' "$tft_firmware"
    rg -q '^const uint8_t TFT_RST = 14;$' "$tft_firmware"
    rg -q '^const uint8_t TFT_SCK = 12;$' "$tft_firmware"
    rg -q '^const uint8_t TFT_MOSI = 11;$' "$tft_firmware"
    rg -q '^const uint8_t TFT_MISO = 13;$' "$tft_firmware"
    rg -q 'Serial protocol from keyboard-midi-controller' "$tft_firmware"
    rg -q '^const uint8_t NOTE_BASE = 36;$' "$tft_firmware"
    rg -q '^const uint8_t NOTE_COUNT = 64;$' "$tft_firmware"
    rg -q '^const uint8_t MIDI_EDITOR_GRID_CC = 90;$' "$tft_firmware"
    rg -q 'sscanf\(line, "S %d %d %d %d"' "$tft_firmware"
    rg -q 'sscanf\(line, "N %d %d"' "$tft_firmware"
    rg -q 'sscanf\(line, "P %d %d %d"' "$tft_firmware"
    rg -q 'sscanf\(line, "K %d %d %d"' "$tft_firmware"
    rg -q '^const uint8_t CC_BASE = 10;$' "$tft_firmware"
    rg -q 'midiEditorGridLabel' "$tft_firmware"
    rg -q 'midiEditorGridTypeLabel' "$tft_firmware"
    rg -q 'if \(channel == 10\)' "$tft_firmware"
    rg -q 'noteInBank == 0 \|\| noteInBank == 1 \|\| noteInBank == 7 \|\| noteInBank >= 8' "$tft_firmware"
    rg -q 'if \(channel == 11\)' "$tft_firmware"
    rg -q 'return noteInBank <= 13;' "$tft_firmware"
    rg -q 'if \(channel == 12\)' "$tft_firmware"
    rg -q 'TRIM L' "$tft_firmware"
    rg -q 'ADD L' "$tft_firmware"
    rg -q 'ONE L' "$tft_firmware"
    rg -q 'COMP' "$tft_firmware"
    rg -q 'DEL L' "$tft_firmware"
    rg -q 'REMOVE' "$tft_firmware"
    rg -q '1/256' "$tft_firmware"
    rg -q '1/512' "$tft_firmware"
    rg -q 'drawBadge\(5, "PLAY"' "$tft_firmware"
    [[ -s "$reaper_startup_script" ]]
    [[ -s "$midi_editor_state_feedback" ]]
    [[ -s "$item_state_feedback" ]]
    [[ -s "$project_transport_state_feedback" ]]
    rg -q 'midi_editor_state_feedback\.lua' "$reaper_startup_script"
    rg -q 'item_state_feedback\.lua' "$reaper_startup_script"
    rg -q 'project_transport_state_feedback\.lua' "$reaper_startup_script"
    rg -q 'MIDIEditor_GetActive' "$midi_editor_state_feedback"
    ! rg -q 'MIDIEditor_GetMode' "$midi_editor_state_feedback"
    rg -q 'MIDIEditor_GetTake' "$midi_editor_state_feedback"
    rg -q 'MIDI_GetGrid' "$midi_editor_state_feedback"
    rg -q '32768' "$midi_editor_state_feedback"
    rg -q 'GetMediaItemTake_Item' "$midi_editor_state_feedback"
    rg -q 'TimeMap2_timeToBeats' "$midi_editor_state_feedback"
    rg -q 'snap_enabled' "$midi_editor_state_feedback"
    rg -q 'cache_home = os.getenv\("XDG_CACHE_HOME"\)' "$midi_editor_state_feedback"
    rg -q 'dotfiles/keyboard-midi-controller/keyboard-midi-controller' "$midi_editor_state_feedback"
    rg -q 'feedback-note %d %d %d' "$midi_editor_state_feedback"
    rg -q 'feedback-cc %d %d %d' "$midi_editor_state_feedback"
    rg -q 'active_poll_interval = 0\.08' "$midi_editor_state_feedback"
    rg -q 'idle_poll_interval = 0\.50' "$midi_editor_state_feedback"
    rg -q 'selected_items_state' "$item_state_feedback"
    rg -q 'CountSelectedMediaItems' "$item_state_feedback"
    rg -q 'GetSelectedMediaItem' "$item_state_feedback"
    rg -q '"B_MUTE"' "$item_state_feedback"
    rg -q '"C_LOCK"' "$item_state_feedback"
    ! rg -q 'one_lane = 45' "$item_state_feedback"
    ! rg -q 'C_LANEPLAYS:%d' "$item_state_feedback"
    rg -q 'local channel = 12' "$item_state_feedback"
    rg -q 'lock = 43' "$item_state_feedback"
    rg -q 'feedback-note %d %d %d' "$item_state_feedback"
    rg -q 'local channel = 10' "$project_transport_state_feedback"
    rg -q 'metronome = 41' "$project_transport_state_feedback"
    rg -q 'metronome_badge = 95' "$project_transport_state_feedback"
    rg -q 'metronome_action_id = 40364' "$project_transport_state_feedback"
    rg -q 'GetToggleCommandStateEx' "$project_transport_state_feedback"
    rg -q 'RefreshToolbar2' "$project_transport_state_feedback"
    rg -q 'feedback-note %d %d %d' "$project_transport_state_feedback"
    rg -q 'midi_editor_state_feedback\.lua' "$sws_task"
    rg -q 'item_state_feedback\.lua' "$sws_task"
    rg -q 'project_transport_state_feedback\.lua' "$sws_task"
    ! rg -q 'allow REAPER sandbox to publish keyboard MIDI feedback|keyboard-midi-controller' "$sws_task"
    rg -q 'whitelist \$\{HOME\}/\.cache/dotfiles/keyboard-midi-controller' "$wine_reaper_firejail_template"
    rg -q 'keyboard MIDI LED matrix firmware' "$embedded_task"
    rg -q 'keyboard MIDI TFT display firmware' "$embedded_task"
    rg -q 'https://espressif.github.io/arduino-esp32/package_esp32_index.json' "$embedded_task"
    rg -q 'arduino-cli board list' "$embedded_task"
    rg -q 'arduino:avr:micro' "$embedded_task"
    rg -q 'esp32:esp32' "$embedded_task"
    rg -q 'esp32:esp32:esp32s3' "$embedded_task"
    rg -q 'Adafruit BusIO' "$embedded_task"
    rg -q 'Adafruit GFX Library' "$embedded_task"
    rg -q 'Adafruit ILI9341' "$embedded_task"
    rg -q 'keyboard-midi-led-matrix/keyboard-midi-led-matrix\.ino' "$embedded_task"
    rg -q 'keyboard-midi-led-matrix\.sha256' "$embedded_task"
    rg -q 'keyboard-midi-tft-display/keyboard-midi-tft-display\.ino' "$embedded_task"
    rg -q 'keyboard-midi-tft-display\.sha256' "$embedded_task"
    rg -q 'arduino-cli.*compile|compile' "$embedded_task"
    rg -q 'arduino-cli.*upload|upload' "$embedded_task"
    rg -q '^Restart=always$' "$readline_notify_service"
    rg -q '^RestartSec=1$' "$readline_notify_service"
    rg -q '^Wants=keyd.service$' "$readline_notify_service"
    rg -q '^After=graphical.target keyd.service$' "$readline_notify_service"
    rg -q '^while :; do$' "$readline_notify_watcher"
    rg -q '^    /usr/local/bin/keyd listen \| while IFS= read -r line; do$' "$readline_notify_watcher"
    rg -q 'run_as_user show_readline_osd.sh' "$readline_notify_watcher"
    rg -q 'run_as_user hide_readline_osd.sh' "$readline_notify_watcher"
    rg -q '^    sleep 1$' "$readline_notify_watcher"
    ! rg -q '/usr/bin/rg|echo "\$LINE"|while read LINE' "$readline_notify_watcher"
    rg -q 'ExecStart=%h/bin/mode-osd run' "$mode_osd_unit"
    rg -q 'Environment="DISPLAY=:0"' "$mode_osd_unit"
    rg -q 'Environment="XAUTHORITY=%h/.Xauthority"' "$mode_osd_unit"
    rg -q '^Restart=on-failure$' "$mode_osd_unit"
    rg -q 'mode-osd.service' "$keyboard_task"
    rg -q 'handler_restart_mode_osd_service' "$keyboard_task"
    rg -q '^- name: handler_restart_mode_osd_service$' "$handlers_file"
    rg -q -- '--compile-cache' "$mode_osd"
    rg -q '^run\)$' "$mode_osd"
    rg -q 'XFixesSetWindowShapeRegion\(display, win, ShapeInput' "$mode_osd"
    rg -q 'attrs\.override_redirect = True' "$mode_osd"
    rg -q 'XStoreName\(display, win, "dotfiles-mode-osd"\)' "$mode_osd"
    rg -q '_NET_WM_WINDOW_OPACITY' "$mode_osd"
    rg -q '_NET_WM_STATE_ABOVE' "$mode_osd"
    rg -q 'XMapRaised\(display, win\)' "$mode_osd"
    rg -q 'XRaiseWindow\(display, win\)' "$mode_osd"
    rg -q 'runtime_dir="\$\{XDG_RUNTIME_DIR:-/run/user/\$\(id -u\)\}"' "$mode_osd"
    rg -q 'state_dir="\$\{DOTFILES_MODE_OSD_STATE_DIR:-\$runtime_dir/dotfiles-mode-osd\}"' "$mode_osd"
    rg -q 'int icon_size = env_int\("DOTFILES_MODE_OSD_ICON_SIZE", 32, 24, 128\);' "$mode_osd"
    rg -q 'int gap = env_int\("DOTFILES_MODE_OSD_GAP", 0, 0, 64\);' "$mode_osd"
    rg -q 'int padding = env_int\("DOTFILES_MODE_OSD_PADDING", 0, 0, 64\);' "$mode_osd"
    rg -q 'const char \*labels\[\] = \{"MS", "RL", "MI"\};' "$mode_osd"
    rg -q 'XSetForeground\(display, gc, visual_pixel\(0, 0, 0\)\);' "$mode_osd"
    rg -q 'fill_x11_rect\(display, win, gc, x, padding, icon_size, icon_size, bg_r,' "$mode_osd"
    rg -q 'valid_mode "\$2"' "$mode_osd"
    rg -q 'exec "\$mode_osd" show mouse' "$show_mouseless_osd"
    rg -q 'exec "\$mode_osd" hide mouse' "$hide_mouseless_osd"
    rg -q 'exec "\$mode_osd" show readline' "$show_readline_osd"
    rg -q 'exec "\$mode_osd" hide readline' "$hide_readline_osd"
    rg -q 'exec "\$mode_osd" show midi' "$show_keyboard_midi_osd"
    rg -q 'exec "\$mode_osd" hide midi' "$hide_keyboard_midi_osd"
    ! rg -q 'org.freedesktop.Notifications|Notify|CloseNotification|redis-cli|notification_id|assets/icons/osd|input-mouse|input-keyboard|audio-card' "$show_mouseless_osd" "$hide_mouseless_osd" "$show_readline_osd" "$hide_readline_osd" "$show_keyboard_midi_osd" "$hide_keyboard_midi_osd"
    ! rg -q '^\[(mouseless_mode|readline_mode|keyboard_midi_mode)\]$|show_mouseless_osd|show_readline_osd|show_keyboard_midi_osd|assets/icons/osd|input-mouse|input-keyboard|audio-card' "$dunst_config"
    ! rg -q 'cursor_indicator' "$show_mouseless_osd" "$hide_mouseless_osd" "$show_readline_osd" "$hide_readline_osd" "$show_keyboard_midi_osd" "$hide_keyboard_midi_osd"
    [[ ! -e "$cursor_indicator_unit" ]]
    [[ ! -e "$cursor_indicator_source_dir" ]]
    [[ ! -e "$cursor_indicator_source" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
