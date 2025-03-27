#!/bin/sh

# https://www.reddit.com/r/Ubuntu/comments/n4qgfe/my_solution_to_get_faster_keyboard_key_input/
xset r rate 190 50
setxkbmap -option compose:menu
