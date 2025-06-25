#!/bin/sh

# Description: Interact with neovim server from other applications
#
# Debugging tips:
#   Use `exec >/tmp/open_in_nvim.out 2>&1` to log output into file. You can then run
#   `watch -n 1 -d cat /tmp/open_in_nvim.out` to see the logs in realtime.

app="$1"
focus_tmux_pane='tmux select-window -t {start}\; if-shell -F "#{&&:#{>:#{pane_index},0},#{window_zoomed_flag}}" "resize-pane -Z" "" \; select-pane -t {top-left}'
servername=$(echo $CUSTOM_NVIM_LISTEN_ADDRESS)

shift
custom_edit="lua vim.cmd.edit({ [[$1]], mods = { emsg_silent = true }})" # don't use `nvr --remote` because it doesn't respect shortmess

case $app in
nnn_search)
    nvr --servername $servername --nostart -c ":lua require'serranomorante.utils'.nnn_search_in_dir('$1', '$PWD/$nnn')"
    nvim --server $servername --remote-send '<C-\><C-n><C-q>'
    ;;
nnn_explorer)
    nvim --server $servername --remote-send '<C-\><C-n><C-q>'
    nvr --servername $servername --nostart -c "$custom_edit"
    ;;
git_editor)
    eval $focus_tmux_pane
    nvr --servername $servername --nostart --remote-tab-wait-silent "$1"
    ;;
lazygit_edit)
    # exec >~/open-in-nvim.out 2>&1
    # echo "$1"
    nvr --servername $servername --nostart -c "$custom_edit" | eval $focus_tmux_pane
    ;;
lazygit_edit_at_line)
    # exec >~/open-in-nvim.out 2>&1
    # echo "$1"
    nvr --servername $servername --nostart -cc "$custom_edit" -c "$2" | eval $focus_tmux_pane
    ;;
lazygit_edit_at_line_and_wait)
    nvr --servername $servername --nostart --remote-wait "$1" -c "$2" | eval $focus_tmux_pane
    ;;
lazygit_open)
    nvr --servername $servername --nostart -c "$custom_edit" | eval $focus_tmux_pane
    ;;
lazygit_open_dir_in_editor)
    nvr --servername $servername --nostart "$1" | eval $focus_tmux_pane
    ;;
lazygit_compare_branch)
    nvr --servername $servername --nostart -c "DiffviewFileHistory --range=HEAD...$1 --right-only --no-merges" | eval $focus_tmux_pane
    ;;
lazygit_open_merge_tool)
    nvr --servername $servername --nostart -cc "$custom_edit" -c "DiffviewOpen" | eval $focus_tmux_pane
    ;;
lazygit_open_difftool)
    nvr --servername $servername --nostart -cc "$custom_edit" -c "DiffviewOpen" | eval $focus_tmux_pane
    ;;
lazygit_diff_against_parent)
    nvr --servername $servername --nostart -c "DiffviewOpen $1^!" | eval $focus_tmux_pane
    ;;
lazygit_diff_with_local_copy)
    nvr --servername $servername --nostart -cc "$custom_edit" -c "DiffviewOpen "$2" -- %" | eval $focus_tmux_pane
    ;;
*)
    nvim --server $servername --remote "$@"
    ;;
esac
