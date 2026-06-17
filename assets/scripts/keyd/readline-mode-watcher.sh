#!/bin/sh
# Purpose: Watch keyd readline layer events and mirror them to the mode OSD.
# Notes: keyd restarts briefly remove /var/run/keyd.socket, so keep this
# process alive and retry instead of letting systemd hit its start limit.

username="{{ ansible_facts.env.USER }}"
home="{{ ansible_facts.env.HOME }}"
uid=$(id -u "$username")

run_as_user() {
    sudo -u "$username" \
        HOME="$home" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        "$home/bin/$1"
}

while :; do
    /usr/local/bin/keyd listen | while IFS= read -r line; do
        case "$line" in
            +readline)
                run_as_user show_readline_osd.sh
                ;;
            -readline)
                run_as_user hide_readline_osd.sh
                ;;
        esac
    done

    sleep 1
done
