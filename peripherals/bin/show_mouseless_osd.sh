#!/bin/sh
# Purpose: Show the persistent mouse-mode overlay.

mode_osd=$(command -v mode-osd || printf '%s\n' "$HOME/dotfiles/peripherals/bin/mode-osd")
exec "$mode_osd" show mouse
