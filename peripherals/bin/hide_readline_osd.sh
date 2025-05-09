#!/bin/sh

id=$(redis-cli get readline_mode_notification_id)

gdbus call --session \
  --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification \
  "$id"

systemctl --user stop cursor_indicator@blue.service
