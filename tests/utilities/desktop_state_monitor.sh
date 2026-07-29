#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities desktop-state shell systemd pipewire
# dotfiles-test-case: desktop-state-monitor-publishes-pipewire-mic-state
# dotfiles-test-case: desktop-state-monitor-publishes-dbus-layer-state
# dotfiles-test-case: desktop-state-monitor-service-contract

# Purpose: Verify the desktop state monitor publishes system-derived state from cheap native watchers.

script="${DOTFILES_TEST_ROOT}/utilities/bin/desktop-state-monitor"
unit="${DOTFILES_TEST_ROOT}/utilities/dot-config/systemd/user/desktop-state-monitor.service"
obs_script="${DOTFILES_TEST_ROOT}/utilities/bin/obs-scene-toggle"
obs_unit="${DOTFILES_TEST_ROOT}/utilities/dot-config/systemd/user/obs-scene-monitor.service"
dotfiles_task="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/30-setup-dotfiles.archlinux.yml"
handlers_file="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/handlers/main.yml"
repository_map="${DOTFILES_TEST_ROOT}/docs/repository-map.md"

wait_for_pattern() {
    local pattern=$1
    local file=$2
    local attempt

    for attempt in $(seq 1 20); do
        rg -q "$pattern" "$file" && return 0
        sleep 0.05
    done

    rg -q "$pattern" "$file"
}

case "${DOTFILES_TEST_CASE:-}" in
desktop-state-monitor-publishes-pipewire-mic-state)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/wpctl" <<'SH'
#!/bin/sh
set -eu

[ "$1" = "get-volume" ] && [ "$2" = "@DEFAULT_AUDIO_SOURCE@" ] || exit 2

count_file="${DOTFILES_TEST_TMP}/wpctl.count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"

if [ "$count" -eq 1 ]; then
  printf 'Volume: 1.00\n'
else
  printf 'Volume: 1.00 [MUTED]\n'
fi
SH

    cat >"${fake_bin}/pw-dump" <<'SH'
#!/bin/sh
set -eu

[ "$1" = "--monitor" ] || exit 2
printf '%s\n' '[{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source"},"params":{"Props":[{"mute":false}]}}}]'
printf '%s\n' '[{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source"},"params":{"Props":[{"mute":true}]}}}]'
SH

    cat >"${fake_bin}/jq" <<'SH'
#!/bin/sh
cat >/dev/null
printf 'pipewire\n'
printf 'pipewire\n'
SH

    cat >"${fake_bin}/keyboard-midi-controller" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_STATE_MONITOR_TEST_FEEDBACK_LOG"
SH
    cat >"${fake_bin}/dbus-monitor" <<'SH'
#!/bin/sh
exit 0
SH

    chmod +x "${fake_bin}/wpctl" "${fake_bin}/pw-dump" "${fake_bin}/jq" "${fake_bin}/keyboard-midi-controller" "${fake_bin}/dbus-monitor"

    DESKTOP_STATE_MONITOR_TEST_FEEDBACK_LOG="${DOTFILES_TEST_TMP}/feedback.log" \
      DESKTOP_STATE_MONITOR_FEEDBACK_COMMAND="${fake_bin}/keyboard-midi-controller" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$script" >"${DOTFILES_TEST_TMP}/monitor.out" 2>"${DOTFILES_TEST_TMP}/monitor.err"

    rg -q '^desktop-action-state 0 MODE BASE$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^desktop-action-state 1 MIC LIVE$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^desktop-action-state 1 MIC MUTED$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^desktop-action-state 2 SHOT READY$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^desktop-action-state 3 REC IDLE$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q '^desktop-action-state 4 MON UNKNOWN$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q 'watching PipeWire default-source events' "${DOTFILES_TEST_TMP}/monitor.err"
    ;;
desktop-state-monitor-publishes-dbus-layer-state)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"

    cat >"${fake_bin}/wpctl" <<'SH'
#!/bin/sh
printf 'Volume: 1.00 [MUTED]\n'
SH
    cat >"${fake_bin}/pw-dump" <<'SH'
#!/bin/sh
[ "$1" = "--monitor" ] || exit 2
exit 0
SH
    cat >"${fake_bin}/jq" <<'SH'
#!/bin/sh
cat >/dev/null
SH
    cat >"${fake_bin}/xrandr" <<'SH'
#!/bin/sh
cat <<'OUT'
Screen 0: minimum 8 x 8, current 3440 x 1440, maximum 32767 x 32767
eDP-1 connected
HDMI-1 connected primary 3440x1440+0+0
OUT
SH
    cat >"${fake_bin}/record-screen-ffmpeg" <<'SH'
#!/bin/sh
case "$1" in
  status)
    printf 'id=record-screen-test\n'
    printf 'pid=1\n'
    printf 'state=recording\n'
    ;;
  *)
    exit 2
    ;;
esac
SH
    cat >"${fake_bin}/dbus-monitor" <<'SH'
#!/bin/sh
cat <<'OUT'
signal time=1.0 sender=:1.1 -> destination=(null destination) serial=1 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "desktop.action"
   string "START"
   string "mic-toggle"
signal time=1.1 sender=:1.1 -> destination=(null destination) serial=2 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "desktop.layer"
   string "SHIFT"
   string ""
signal time=1.2 sender=:1.1 -> destination=(null destination) serial=3 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "desktop.action"
   string "START"
   string "screenshot"
signal time=1.3 sender=:1.1 -> destination=(null destination) serial=4 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "desktop.action"
   string "START"
   string "record-toggle"
signal time=1.4 sender=:1.1 -> destination=(null destination) serial=5 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "screen.recording"
   string "recording"
   string ""
signal time=1.5 sender=:1.1 -> destination=(null destination) serial=6 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "desktop.action"
   string "START"
   string "monitor-toggle"
signal time=1.6 sender=:1.1 -> destination=(null destination) serial=7 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "display.layout"
   string "EXT"
   string "HDMI-1"
signal time=1.7 sender=:1.1 -> destination=(null destination) serial=8 path=/org/dotfiles/DesktopAction; interface=org.dotfiles.DesktopAction; member=Event
   string "screenshot.capture"
   string "SAVED"
   string "/tmp/screenshot.png"
OUT
SH
    cat >"${fake_bin}/keyboard-midi-controller" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_STATE_MONITOR_TEST_FEEDBACK_LOG"
SH
    chmod +x "${fake_bin}/wpctl" "${fake_bin}/pw-dump" "${fake_bin}/jq" "${fake_bin}/xrandr" "${fake_bin}/record-screen-ffmpeg" "${fake_bin}/dbus-monitor" "${fake_bin}/keyboard-midi-controller"

    DESKTOP_STATE_MONITOR_TEST_FEEDBACK_LOG="${DOTFILES_TEST_TMP}/feedback.log" \
      DESKTOP_STATE_MONITOR_RECORD_SCRIPT="${fake_bin}/record-screen-ffmpeg" \
      DESKTOP_STATE_MONITOR_FEEDBACK_COMMAND="${fake_bin}/keyboard-midi-controller" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$script" >"${DOTFILES_TEST_TMP}/monitor.out" 2>"${DOTFILES_TEST_TMP}/monitor.err"

    wait_for_pattern '^desktop-action-state 0 MODE SHIFT$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 1 MIC BUSY$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 1 MIC MUTED$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 2 SHOT READY$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 2 SHOT BUSY$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 2 SHOT SAVED$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 3 REC BUSY$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 3 REC REC$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 4 MON BUSY$' "${DOTFILES_TEST_TMP}/feedback.log"
    wait_for_pattern '^desktop-action-state 4 MON EXT$' "${DOTFILES_TEST_TMP}/feedback.log"
    rg -q 'watching desktop action DBus events' "${DOTFILES_TEST_TMP}/monitor.err"
    ;;
desktop-state-monitor-service-contract)
    [[ -x "$script" ]]
    bash -n "$script"
    rg -q 'pw-dump --monitor' "$script"
    rg -q 'jq --unbuffered' "$script"
    rg -q 'dbus-monitor --session' "$script"
    rg -q 'wpctl get-volume @DEFAULT_AUDIO_SOURCE@' "$script"
    rg -q 'desktop-action-state "\$slot" "\$label" "\$value"' "$script"
    rg -q 'desktop_layer=BASE' "$script"
    rg -q 'local next_layer' "$script"
    rg -q '\[ "\$next_layer" != "\$desktop_layer" \] \|\| return 0' "$script"
    rg -q 'publish_desktop_action_state 0 MODE "\$desktop_layer"' "$script"
    rg -q 'publish_desktop_action_state 1 MIC "\$mic_state"' "$script"
    rg -q 'publish_desktop_action_state 2 SHOT "\$screenshot_state"' "$script"
    rg -q 'publish_desktop_action_state 3 REC "\$record_state"' "$script"
    rg -q 'publish_desktop_action_state 4 MON "\$display_state"' "$script"
    rg -q 'desktop.action' "$script"
    rg -q 'START:mic-toggle' "$script"
    rg -q 'publish_desktop_action_state 1 MIC BUSY' "$script"
    rg -q 'START:screenshot' "$script"
    rg -q 'publish_desktop_action_state 2 SHOT BUSY' "$script"
    rg -q 'START:record-toggle' "$script"
    rg -q 'publish_desktop_action_state 3 REC BUSY' "$script"
    rg -q 'START:monitor-toggle' "$script"
    rg -q 'publish_desktop_action_state 4 MON BUSY' "$script"
    rg -q 'desktop.layer' "$script"
    rg -q 'screen.recording' "$script"
    rg -q 'display.layout' "$script"
    rg -q 'screenshot.capture' "$script"
    rg -q 'screenshot_state=READY' "$script"
    refute rg -q 'while .*sleep|sleep [0-9]' "$script"
    [[ -s "$unit" ]]
    rg -q '^Description=Publish desktop state feedback$' "$unit"
    rg -q '^After=graphical-session.target pipewire.service wireplumber.service$' "$unit"
    rg -q '^ExecStart=%h/bin/desktop-state-monitor$' "$unit"
    rg -q '^Restart=on-failure$' "$unit"
    rg -q '^WantedBy=graphical-session.target$' "$unit"
    [[ -x "$obs_script" ]]
    rg -q -- "--monitor" "$obs_script"
    rg -q "desktop-action-state" "$obs_script"
    rg -F -q "publish_scene(args.feedback_command, target)" "$obs_script"
    rg -q "CurrentProgramSceneChanged" "$obs_script"
    [[ -s "$obs_unit" ]]
    rg -q "^Description=Publish OBS scene feedback$" "$obs_unit"
    rg -q "^ExecStart=%h/bin/obs-scene-toggle --monitor$" "$obs_unit"
    rg -q "^Restart=on-failure$" "$obs_unit"
    rg -q 'Dotfiles: ensure desktop state monitor' "$dotfiles_task"
    rg -q '^    name: desktop-state-monitor.service$' "$dotfiles_task"
    rg -q "Dotfiles: ensure OBS scene monitor" "$dotfiles_task"
    rg -q "^    name: obs-scene-monitor.service$" "$dotfiles_task"
    rg -q 'Dotfiles: stat desktop state monitor files' "$dotfiles_task"
    rg -q 'utilities/bin/desktop-state-monitor' "$dotfiles_task"
    rg -q 'utilities/dot-config/systemd/user/desktop-state-monitor.service' "$dotfiles_task"
    rg -q "utilities/bin/obs-scene-toggle" "$dotfiles_task"
    rg -q "utilities/dot-config/systemd/user/obs-scene-monitor.service" "$dotfiles_task"
    rg -q 'desktop-state-monitor-sha256' "$dotfiles_task"
    rg -q 'handler_restart_desktop_state_monitor_service' "$dotfiles_task"
    rg -q "handler_restart_obs_scene_monitor_service" "$dotfiles_task"
    rg -q '^- name: handler_restart_desktop_state_monitor_service$' "$handlers_file"
    rg -q "^- name: handler_restart_obs_scene_monitor_service$" "$handlers_file"
    rg -q 'Prefer event-driven desktop state monitors' "$repository_map"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
