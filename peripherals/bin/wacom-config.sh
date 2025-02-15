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
speed_prop_id=$(xinput list-props "${stylus}" | grep "Constant Deceleration" | grep -Po '\(\K[^\)]+')

if [ -z "${pad}" ]; then
    exit 0
fi

# configure the buttons on ${stylus} with your xsetwacom commands...
#xsetwacom set "${stylus}" Button 2 11
#...

# Enable relative mode (aka "mouse mode")
# https://support.wacom.com/hc/en-us/articles/1500006340122-What-is-Absolute-Positioning
xsetwacom --set "${stylus_name}" Mode "Relative"

# Scroll like using the mouse
# https://askubuntu.com/questions/458460/wacom-tablet-middle-mouse-button-scrolling
xsetwacom --set "${stylus_name}" Button 2 "pan"
xsetwacom --set "${stylus_name}" "PanScrollThreshold" 200

# Decelerate pointer speed (from 1.0 to 1.8)
xinput set-prop "${stylus}" "${speed_prop_id}" 1.8
