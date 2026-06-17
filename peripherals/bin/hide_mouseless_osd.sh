#!/bin/sh
# Purpose: Hide the persistent mouse-mode overlay.

mode_osd=$(command -v mode-osd || printf '%s\n' "$HOME/dotfiles/peripherals/bin/mode-osd")
exec "$mode_osd" hide mouse
