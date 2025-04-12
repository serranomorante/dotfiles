#!/bin/sh

tty="$(tty)"
id="$(
  gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    show_readline_osd \
    0 \
    accessories-dictionary \
    "Readline Mode" \
    "Readline mode enabled" \
    [] \
    {} \
    0
)"
id="${id##* }"
id="${id%,)}"

redis-cli set readline_mode_notification_id $id
