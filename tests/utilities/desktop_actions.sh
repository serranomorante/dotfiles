#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities desktop-state shell
# dotfiles-test-case: desktop-action-event-emits-dbus-signal
# dotfiles-test-case: desktop-action-run-mic-toggle
# dotfiles-test-case: desktop-action-run-screenshot
# dotfiles-test-case: desktop-action-run-obs-scene-toggle
# dotfiles-test-case: desktop-action-run-record-stop
# dotfiles-test-case: desktop-action-run-monitor-toggle

# Purpose: Verify generic desktop action helpers used by the pedalboard desktop profile.

event_script="${DOTFILES_TEST_ROOT}/utilities/bin/desktop-action-event"
run_script="${DOTFILES_TEST_ROOT}/utilities/bin/desktop-action-run"

case "${DOTFILES_TEST_CASE:-}" in
desktop-action-event-emits-dbus-signal)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/gdbus" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"$DESKTOP_ACTION_TEST_GDBUS_LOG"
SH
    chmod +x "${fake_bin}/gdbus"

    DESKTOP_ACTION_TEST_GDBUS_LOG="${DOTFILES_TEST_TMP}/gdbus.log" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$event_script" screen.recording REC record-screen-test

    rg -q -- '--session' "${DOTFILES_TEST_TMP}/gdbus.log"
    rg -q -- '--object-path /org/dotfiles/DesktopAction' "${DOTFILES_TEST_TMP}/gdbus.log"
    rg -q -- '--signal org.dotfiles.DesktopAction.Event' "${DOTFILES_TEST_TMP}/gdbus.log"
    rg -q -- 'screen.recording REC record-screen-test' "${DOTFILES_TEST_TMP}/gdbus.log"
    ;;
desktop-action-run-mic-toggle)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/wpctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_WPCTL_LOG"
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_EVENT_LOG"
SH
    chmod +x "${fake_bin}/wpctl" "${fake_bin}/desktop-action-event"

    DESKTOP_ACTION_TEST_WPCTL_LOG="${DOTFILES_TEST_TMP}/wpctl.log" \
      DESKTOP_ACTION_TEST_EVENT_LOG="${DOTFILES_TEST_TMP}/events.log" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$run_script" mic-toggle >"${DOTFILES_TEST_TMP}/mic.out"

    rg -q '^desktop.action START mic-toggle$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^set-mute @DEFAULT_AUDIO_SOURCE@ toggle$' "${DOTFILES_TEST_TMP}/wpctl.log"
    ;;
desktop-action-run-screenshot)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    pictures="${DOTFILES_TEST_TMP}/Pictures"
    mkdir -p "$fake_bin" "$pictures"
    cat >"${fake_bin}/spectacle" <<'SH'
#!/bin/sh
output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    *)
      printf '%s\n' "$1" >>"$DESKTOP_ACTION_TEST_SPECTACLE_ARGS"
      shift
      ;;
  esac
done
[ -n "$output" ] || exit 2
printf '%s\n' "$output" >"$DESKTOP_ACTION_TEST_SCREENSHOT_PATH"
: >"$output"
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_EVENT_LOG"
SH
    cat >"${fake_bin}/xdg-user-dir" <<'SH'
#!/bin/sh
[ "$1" = PICTURES ] || exit 2
printf '%s\n' "$DESKTOP_ACTION_TEST_XDG_PICTURES_DIR"
SH
    chmod +x "${fake_bin}/spectacle" "${fake_bin}/desktop-action-event" "${fake_bin}/xdg-user-dir"

      DESKTOP_ACTION_TEST_SPECTACLE_ARGS="${DOTFILES_TEST_TMP}/spectacle.args" \
      DESKTOP_ACTION_TEST_SCREENSHOT_PATH="${DOTFILES_TEST_TMP}/screenshot.path" \
      DESKTOP_ACTION_TEST_EVENT_LOG="${DOTFILES_TEST_TMP}/events.log" \
      DESKTOP_ACTION_TEST_XDG_PICTURES_DIR="$pictures" \
      XDG_PICTURES_DIR="${HOME}/~/Pictures" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$run_script" screenshot >"${DOTFILES_TEST_TMP}/screenshot.out"

    screenshot_path=$(cat "${DOTFILES_TEST_TMP}/screenshot.path")
    [[ -f "$screenshot_path" ]]
    [[ "$screenshot_path" == "$pictures"/screenshot_*.png ]]
    rg -q '^-b$' "${DOTFILES_TEST_TMP}/spectacle.args"
    rg -q '^-f$' "${DOTFILES_TEST_TMP}/spectacle.args"
    rg -q '^-n$' "${DOTFILES_TEST_TMP}/spectacle.args"
    rg -q '^desktop.action START screenshot$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q "^screenshot.capture SAVED ${screenshot_path}$" "${DOTFILES_TEST_TMP}/events.log"
    ;;
desktop-action-run-obs-scene-toggle)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/obs-scene-toggle" <<'SH'
#!/bin/sh
printf 'obs toggled\n'
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_EVENT_LOG"
SH
    chmod +x "${fake_bin}/obs-scene-toggle" "${fake_bin}/desktop-action-event"

    DESKTOP_ACTION_OBS_SCENE_TOGGLE="${fake_bin}/obs-scene-toggle" \
      DESKTOP_ACTION_TEST_EVENT_LOG="${DOTFILES_TEST_TMP}/events.log" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$run_script" obs-scene-toggle >"${DOTFILES_TEST_TMP}/obs.out"

    rg -q '^obs toggled$' "${DOTFILES_TEST_TMP}/obs.out"
    rg -q '^desktop.action START obs-scene-toggle$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
desktop-action-run-record-stop)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/record-screen-ffmpeg" <<'SH'
#!/bin/sh
case "$1" in
  status)
    printf 'id=record-screen-test\n'
    printf 'pid=1\n'
    printf 'state=recording\n'
    ;;
  stop)
    printf 'stop\n' >>"$DESKTOP_ACTION_TEST_RECORD_LOG"
    ;;
  *)
    exit 2
    ;;
esac
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_EVENT_LOG"
SH
    chmod +x "${fake_bin}/record-screen-ffmpeg" "${fake_bin}/desktop-action-event"

    DESKTOP_ACTION_RECORD_SCRIPT="${fake_bin}/record-screen-ffmpeg" \
      DESKTOP_ACTION_TEST_RECORD_LOG="${DOTFILES_TEST_TMP}/record.log" \
      DESKTOP_ACTION_TEST_EVENT_LOG="${DOTFILES_TEST_TMP}/events.log" \
    PATH="${fake_bin}:/usr/bin:/bin" \
      "$run_script" record-toggle >"${DOTFILES_TEST_TMP}/record.out"

    rg -q '^stop$' "${DOTFILES_TEST_TMP}/record.log"
    rg -q '^desktop.action START record-toggle$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^screen.recording STOPPING$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
desktop-action-run-monitor-toggle)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/present-window" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_PRESENT_LOG"
SH
    cat >"${fake_bin}/setup-displays.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_SETUP_LOG"
printf 'layout toggled\n'
SH
    cat >"${fake_bin}/desktop-action-event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DESKTOP_ACTION_TEST_EVENT_LOG"
SH
    chmod +x "${fake_bin}/present-window" "${fake_bin}/setup-displays.sh" "${fake_bin}/desktop-action-event"

    DESKTOP_ACTION_PRESENT_WINDOW="${fake_bin}/present-window" \
      DESKTOP_ACTION_SETUP_DISPLAYS="${fake_bin}/setup-displays.sh" \
      DESKTOP_ACTION_TEST_PRESENT_LOG="${DOTFILES_TEST_TMP}/present.log" \
      DESKTOP_ACTION_TEST_SETUP_LOG="${DOTFILES_TEST_TMP}/setup.log" \
      DESKTOP_ACTION_TEST_EVENT_LOG="${DOTFILES_TEST_TMP}/events.log" \
      PATH="${fake_bin}:/usr/bin:/bin" \
      "$run_script" monitor-toggle >"${DOTFILES_TEST_TMP}/monitor.out"

    rg -q '^clear$' "${DOTFILES_TEST_TMP}/present.log"
    rg -q '^--toggle$' "${DOTFILES_TEST_TMP}/setup.log"
    rg -q '^layout toggled$' "${DOTFILES_TEST_TMP}/monitor.out"
    rg -q '^desktop.action START monitor-toggle$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
