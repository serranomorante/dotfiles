#!/bin/sh

export $(dbus-launch)

/usr/bin/keyd listen | while read LINE; do
    readline_mode_enter=$(echo "$LINE" | /usr/bin/rg "\+readline")
    readline_mode_exit=$(echo "$LINE" | /usr/bin/rg "\-readline")

    if [ ! -z "$readline_mode_enter" ]; then
        bash ~/bin/show_readline_osd.sh
    fi

    if [ ! -z "$readline_mode_exit" ]; then
        bash ~/bin/hide_readline_osd.sh
    fi
done
