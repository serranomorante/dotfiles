#!/bin/bash

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
xsetwacom --set "${stylus_name}" Mode "Relative"

# Use stylus to scroll
xsetwacom --set "${stylus_name}" Button 2 "pan"
xsetwacom --set "${stylus_name}" "PanScrollThreshold" 200

# Disable stylus buttons
xsetwacom --set "${stylus_name}" Button 3 "0"

# Disable tablet buttons
xsetwacom --set "${pad_name}" Button 1 "0"
xsetwacom --set "${pad_name}" Button 2 "0"
xsetwacom --set "${pad_name}" Button 3 "0"
xsetwacom --set "${pad_name}" Button 4 "0"
xsetwacom --set "${pad_name}" Button 5 "0"
xsetwacom --set "${pad_name}" Button 6 "0"
xsetwacom --set "${pad_name}" Button 7 "0"
xsetwacom --set "${pad_name}" Button 8 "0"

full_window_size=$(xrandr -q | grep -Po '\bcurrent\b\s(\d+)\sx\s(\d+)')
x_window_size=$(echo $full_window_size | awk '{print $2}')
y_window_size=$(echo $full_window_size | awk '{print $4}')
speed=$(awk "BEGIN {print $x_window_size/$y_window_size}")

# Decelerate pointer speed
xinput set-prop "${stylus}" "${speed_prop_id}" "$speed"
