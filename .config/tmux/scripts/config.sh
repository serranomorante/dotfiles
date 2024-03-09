#!/bin/bash

# On my .bashrc file:
# alias conf="~/.config/tmux/scripts/config.sh"

session_name="config"
foam="foam"
nvim="nvim"
wait_shell_init=0.3
wait_shell_cmd=0.001

# create session, name window and detach
# tell new-session to use the size of your terminal: https://unix.stackexchange.com/a/569731
tmux new-session -d -n $foam -s $session_name -x "$(tput cols)" -y "$(tput lines)"

# setup "foam" window
# ---------------------
sleep $wait_shell_init # wait for shell to load

tmux send-keys -t "$session_name:$foam" "z foam" Enter # cd into directory

sleep $wait_shell_cmd

tmux send-keys -t "$session_name:$foam" "vim" Enter

# setup "nvim" window
# ---------------------
tmux new-window -t $session_name -n $nvim # this will automatically focus the new window

sleep $wait_shell_init

tmux send-keys -t "$session_name:$nvim" "z nvim" Enter # cd into directory

sleep $wait_shell_cmd

tmux send-keys -t "$session_name:$nvim" "vim" Enter

# Open your session
# ---------------------
tmux attach-session -t $session_name
