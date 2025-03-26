#!/usr/bin/env sh

device=$(libinput list-devices | grep -i "$1" -A10 | grep 'Capabilities.*keyboard .*$' -C 5 | grep "Kernel:" | sed 's_.*\(/dev/input/event[0-9]*\).*_\1_')

if [ -z "$device" ]; then
  echo "device not found"
  exit 1
fi

echo "device found: $device"

sed -i.bak "/- \"$1\"/s|\"$1\"|\"$device\"|" ~/.config/mouseless/config.yaml

if grep -q "$device" ~/.config/mouseless/config.yaml; then
  echo "Config updated successfully: '$1' replaced with '$device'"
else
  echo "Failed to update config"
fi
