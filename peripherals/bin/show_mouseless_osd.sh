#!/bin/sh

tty="$(tty)"
id="$(gdbus call --session \
  --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify \
  my_script \
  0 \
  utilities-terminal \
  "Mouseless" \
  "Mouse mode enabled" \
  [] \
  {} \
  0
)"
id="${id##* }"
id="${id%,)}"

redis-cli set mouseless_mode_notification_id $id
