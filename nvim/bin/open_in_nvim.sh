#!/bin/bash

tmux select-window -t "{start}"
tmux if-shell -F "#{&&:#{>:#{pane_index},0},#{window_zoomed_flag}}" "resize-pane -Z" ""
tmux select-pane -t "{top-left}"
nvr --servername $CUSTOM_NVIM_LISTEN_ADDRESS --nostart --remote-tab-wait-silent "$@"
