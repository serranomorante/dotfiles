#!/bin/sh

# Description: Interact with neovim server from other applications
#
# Debugging tips:
#   Use `exec >/tmp/open_in_nvim.out 2>&1` to log output into file. You can then run
#   `watch -n 1 -d cat /tmp/open_in_nvim.out` to see the logs in realtime.

app="$1"
servername=$(echo $NVIM_KITTY_LISTEN_ADDRESS)

shift
nvim_center_view="vim.cmd.normal({ "zz", bang = true })"
nvim_close_term_win="vim.api.nvim_win_close(0, false)"
nvim_edit="vim.cmd.edit({ [[$1]], mods = { emsg_silent = true }})" # don't use `nvr --remote` because it doesn't respect shortmess

case $app in
nnn_search)
    nvr --servername $servername --nostart -c "NNNSearch $1 $PWD/$nnn"
    ;;
nnn_explorer)
    nvr --servername $servername --nostart -c "lua $nvim_close_term_win; $nvim_edit"
    ;;
git_editor)
    nvr --servername $servername --nostart --remote-tab-wait-silent "$@"
    ;;
lazygit_edit)
    # exec >~/open-in-nvim.out 2>&1
    # echo "$1"
    nvr --servername $servername --nostart -c "lua $nvim_close_term_win; $nvim_edit"
    ;;
lazygit_edit_at_line)
    # exec >~/open-in-nvim.out 2>&1
    # echo "$1"
    nvr --servername $servername --nostart -cc "lua $nvim_close_term_win; $nvim_edit; $nvim_center_view" -c "$2"
    ;;
lazygit_edit_at_line_and_wait)
    nvr --servername $servername --nostart --remote-wait "$1" -c "$2"
    ;;
lazygit_open)
    nvr --servername $servername --nostart -c "lua $nvim_close_term_win; $nvim_edit"
    ;;
lazygit_open_dir_in_editor)
    nvr --servername $servername --nostart "$1"
    ;;
lazygit_compare_branch)
    nvr --servername $servername --nostart -c "DiffviewFileHistory --range=HEAD...$1 --right-only --no-merges"
    ;;
lazygit_open_merge_tool)
    nvr --servername $servername --nostart -cc "lua $nvim_close_term_win; $nvim_edit" -c "DiffviewOpen"
    ;;
lazygit_open_difftool)
    nvr --servername $servername --nostart -cc "lua $nvim_close_term_win; $nvim_edit" -c "DiffviewOpen"
    ;;
lazygit_diff_against_parent)
    nvr --servername $servername --nostart -c "DiffviewOpen $1^!"
    ;;
lazygit_diff_with_local_copy)
    nvr --servername $servername --nostart -cc "lua $nvim_close_term_win" -c "DiffviewOpen $2 -- %"
    ;;
kitty_edit_at_line)
    nvr --servername $servername --nostart -cc "lua $nvim_edit; $nvim_center_view" -c "$2" | kitten @ action goto_tab 1
    ;;
*)
    nvim --server $servername --remote "$@"
    ;;
esac
