#!/bin/sh
# Purpose: Apply this workstation's X keyboard settings at session start.
# Notes: Order matters. setxkbmap reloads the keymap, so the latin keysym block
#        has to run after it or the assignments are discarded.

# https://www.reddit.com/r/Ubuntu/comments/n4qgfe/my_solution_to_get_faster_keyboard_key_input/
xset r rate 190 50
setxkbmap -option compose:menu

# The keyd [spanish] layers type latin characters with `xdotool key <keysym>`.
# When no keycode carries the keysym, xdotool binds a scratch keycode and
# restores it around the keystroke, which keeps the injected key down for up to
# ~130 ms. The repeat delay set above is 190 ms, so under load (a DAW, a busy
# session) the injected key crosses it and one keystroke emits a run of
# characters. Giving each keysym a permanent keycode drops that window to ~0 ms,
# and disabling repeat on those keycodes makes a run impossible even when the
# release is delayed.
latin_keycodes="248 230 222 219 184 183 178 168"

xmodmap - <<'XMODMAP'
keycode 248 = aacute Aacute aacute Aacute
keycode 230 = eacute Eacute eacute Eacute
keycode 222 = iacute Iacute iacute Iacute
keycode 219 = oacute Oacute oacute Oacute
keycode 184 = uacute Uacute uacute Uacute
keycode 183 = ntilde Ntilde ntilde Ntilde
keycode 178 = exclamdown questiondown exclamdown questiondown
keycode 168 = EuroSign EuroSign EuroSign EuroSign
XMODMAP

for keycode in $latin_keycodes; do
    xset -r "$keycode"
done
