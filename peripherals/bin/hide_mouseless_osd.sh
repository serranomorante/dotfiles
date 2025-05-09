#!/bin/sh

id=$(redis-cli get mouseless_mode_notification_id)

gdbus call --session \
  --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification \
  "$id"

systemctl --user stop cursor_indicator@red.service
