# This script is very coupled to the rest of my setup
# Any file that you open in the format: `terminal://<filename>:<line>` will open as a buffer in the
# corresponding nvim instance. Example: `xdg-open terminal://test.md:35`
# Dependencies: xdotool

LINK="$1"
SERVERNAME=/tmp/_home_serranomorante_repos_gems # should be same as `v:servername` of your nvim instance.
FILENAME=$(echo $LINK | sed -E 's/^.*?:([^:]+):.*/\1/g') # extract the filename part
LINE=$(echo $LINK | sed -E 's/^.*:(.*)/\1/g') # extract the line number part
# The next line does the following:
# 1. Targets your specific neovim instance (by the servername)
# 2. Focus the first tab of your targeted nvim instance
# 3. Focus the dwm tag that you use for your code related tasks
# 4. Opens the filename passed as args
# 5. Positions the cursor to the line passed as args
# 6. Executes a shell command from inside vim to focus the first tmux window and the top-left pane (this is a fixed nvim position across all tmux sessions on my setup)
# 7. Also handles any zoomed pane that might block the nvim pane
nvr --nostart --servername $SERVERNAME --remote $FILENAME \
    -cc "1tabnext | silent exec '!xdotool key super+2'" \
    -c "$LINE | silent exec \"!tmux select-window -t {start}\\\; if-shell -F '\\\\#{&&:#{>:#{pane_index},0},#{window_zoomed_flag}}' 'resize-pane -Z' ''\\\; select-pane -t {top-left}\""
