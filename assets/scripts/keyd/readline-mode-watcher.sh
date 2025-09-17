#!/bin/sh

username="{{ ansible_env.USER }}"
uid=$(id -u $username)

/usr/local/bin/keyd listen | while read LINE; do
    readline_mode_enter=$(echo "$LINE" | /usr/bin/rg "\+readline")
    readline_mode_exit=$(echo "$LINE" | /usr/bin/rg "\-readline")

    if [ ! -z "$readline_mode_enter" ]; then
        sudo -u $username DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus ~/bin/show_readline_osd.sh
    fi

    if [ ! -z "$readline_mode_exit" ]; then
        sudo -u $username DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus ~/bin/hide_readline_osd.sh
    fi
done
