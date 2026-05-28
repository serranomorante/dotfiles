#!/bin/bash
# Purpose: Apply runtime-only Wacom Intuos settings after Xorg adds the tablet.
# Notes: Static defaults live in 71-intuos-s-relative.conf. Keep this script for
# xsetwacom actions and settings that depend on the current display layout.

stylus_name="Wacom Intuos S Pen stylus" # hard-coded as this might never change
fallback_deceleration="1.77778"

warn() {
    printf 'wacom-config: %s\n' "$1" >&2
}

device_id_for_name() {
    local name="$1"

    printf '%s\n' "$list" | awk -v name="$name" '
        index($0, name) {
            for (i = 1; i <= NF; i++) {
                if ($i == "id:") {
                    print $(i + 1)
                    exit
                }
            }
        }
    '
}

display_deceleration() {
    local screen_size width height

    screen_size=$(xrandr --query 2>/dev/null | awk '
        /^Screen / {
            for (i = 1; i <= NF; i++) {
                if ($i == "current") {
                    gsub(",", "", $(i + 1))
                    gsub(",", "", $(i + 3))
                    print $(i + 1), $(i + 3)
                    exit
                }
            }
        }
    ')

    width=$(printf '%s\n' "$screen_size" | awk '{print $1}')
    height=$(printf '%s\n' "$screen_size" | awk '{print $2}')

    if [ -n "$width" ] && [ -n "$height" ] && [ "$height" -gt 0 ] 2>/dev/null; then
        awk -v width="$width" -v height="$height" 'BEGIN { printf "%.5f\n", width / height }'
        return
    fi

    printf '%s\n' "$fallback_deceleration"
}

for i in $(seq 10); do
    list=$(xsetwacom list devices 2>/dev/null || true)
    stylus=$(device_id_for_name "$stylus_name")

    if [ -n "${stylus}" ]; then
        break
    fi
    sleep 1
done

if [ -z "${stylus}" ]; then
    warn "did not find ${stylus_name}"
    exit 0
fi

# `pan` is a complex xsetwacom action, so it cannot be expressed as a static
# xorg.conf Button option.
xsetwacom --set "${stylus_name}" Button 2 "pan" >/dev/null 2>&1 || true

deceleration=$(display_deceleration)

if xinput list-props "${stylus}" | grep -q "Device Accel Constant Deceleration"; then
    xinput set-prop "${stylus}" "Device Accel Constant Deceleration" "$deceleration" >/dev/null 2>&1 || true
else
    warn "did not find the 'Constant Deceleration' property for ${stylus_name}"
fi
