#!/bin/bash

warn() {
    printf 'wacom-config: %s\n' "$1" >&2
}

set_button_if_supported() {
    local device="$1"
    local button="$2"
    local action="$3"

    if xsetwacom --get "$device" "Button $button" >/dev/null 2>&1; then
        xsetwacom --set "$device" "Button $button" "$action" >/dev/null 2>&1 || true
    fi
}

for i in $(seq 10); do
    if xsetwacom list devices | grep -q Wacom; then
        break
    fi
    sleep 1
done

list=$(xsetwacom list devices)
pad=$(echo "${list}" | grep Wacom | awk '/pad/{print $7}')
stylus=$(echo "${list}" | grep Wacom | awk '/stylus/{print $7}')

stylus_name="Wacom Intuos S Pen stylus" # hard-coded as this might never change
pad_name="Wacom Intuos S Pad pad"       # hard-coded as this might never change
speed_prop_id=$(xinput list-props "${stylus}" | grep "Constant Deceleration" | grep -Po '\(\K[^\)]+')

if [ -z "${pad}" ]; then
    exit 0
fi

# Enable relative mode (aka "mouse mode")
# https://support.wacom.com/hc/en-us/articles/1500006340122-What-is-Absolute-Positioning
xsetwacom --set "${stylus_name}" Mode "Relative" >/dev/null 2>&1 || true

# Use stylus to scroll
set_button_if_supported "${stylus_name}" 2 "pan"
xsetwacom --set "${stylus_name}" "PanScrollThreshold" 200 >/dev/null 2>&1 || true

# Disable stylus buttons
set_button_if_supported "${stylus_name}" 3 "0"

# Disable tablet buttons
for button in 1 2 3 4 5 6 7 8; do
    set_button_if_supported "${pad_name}" "$button" "0"
done

full_window_size=$(xrandr -q | grep -Po '\bcurrent\b\s(\d+)\sx\s(\d+)')
x_window_size=$(echo $full_window_size | awk '{print $2}')
y_window_size=$(echo $full_window_size | awk '{print $4}')
speed=$(awk "BEGIN {print $x_window_size/$y_window_size}")

# Decelerate pointer speed
if [ -n "${speed_prop_id}" ]; then
    xinput set-prop "${stylus}" "${speed_prop_id}" "$speed" >/dev/null 2>&1 || true
else
    warn "no se encontro propiedad 'Constant Deceleration' para ${stylus_name}"
fi
