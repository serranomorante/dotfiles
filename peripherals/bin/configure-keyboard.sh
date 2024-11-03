#!/bin/sh
# https://wiki.archlinux.org/title/Bluetooth#Wake_from_suspend

export DISPLAY=:0
xset r rate 220 30
setxkbmap -option compose:menu
