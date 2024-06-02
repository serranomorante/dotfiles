# A duplication of ~/.bashrc for fish

set -l brew_ubuntu_path /home/linuxbrew/.linuxbrew/bin/brew

if test -e "$brew_ubuntu_path"; and test -x "$brew_ubuntu_path"
    eval "$($brew_ubuntu_path shellenv)"
end

command -q eza; and abbr --add ls eza -1 -l --icons always --color always
abbr --add grep grep --color=auto
abbr --add cls printf "\033c"

set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin:$PATH"
set -gx PATH "$HOME/bin:$PATH"
set -gx FONTCONFIG_PATH /etc/fonts

# This fixes poetry not being found
set -gx PATH "$HOME/.local/bin:$PATH"

# Add pynvim to path
set -gx PATH "/usr/lib/python3.11/site-packages:$PATH"

# For go packages
command -q go; and set -gx PATH "$PATH:$(go env GOBIN):$(go env GOPATH)/bin"

# system env variables
set -gx SYSTEMD_PAGER ""

# https://wiki.archlinux.org/title/Neovim#Use_as_a_pager
# set -gx PAGER "nvimpager"

# fzf use df instead of find
set -gx FZF_DEFAULT_COMMAND "fd --type f"
set -gx FZF_DEFAULT_OPTS "--layout=reverse --border"
set -gx FZF_DEFAULT_OPTS_FILE "$HOME/.fzfrc"
set -gx RIPGREP_CONFIG_PATH "$HOME/.ripgreprc"

# Wireplumber logging
# 0. critical warnings and fatal errors (C & E in the log)
# 1. warnings (W)
# 2. normal messages (M)
# 3. informational messages (I)
# 4. debug messages (D)
# 5. trace messages (T)
set -gx WIREPLUMBER_DEBUG 3

command -q volta; and set -gx SYSTEM_DEFAULT_NODE_VERSION $(volta list node | grep "default" | cut -d "@" -f 2 | cut -d " " -f 1)

# Add abbreviation for vim
command -q nvim; and abbr --add vim nvim

# Check for the existence of `nvim`, `tmux`, and whether we are inside a tmux session
if command -q nvim; and command -q tmux; and set -q TMUX
    # Check if NVIM_LISTEN_ADDRESS exists in tmux environment, ignoring errors
    if set -l nvim_address_check (tmux show-environment NVIM_LISTEN_ADDRESS 2>/dev/null; or echo "")
        set -gx NVIM_LISTEN_ADDRESS (string split "=" -- $nvim_address_check)[2]

        if string length --quiet "$NVIM_LISTEN_ADDRESS"
            command -q nvr; and nvr --nostart -s --servername $NVIM_LISTEN_ADDRESS

            # Check if there's an existing nvim server
            if test $status -eq 0
                # Connect to existing nvim server if exists
                abbr --add vim nvim --remote-ui --server "$NVIM_LISTEN_ADDRESS"
            else
                # Create a new nvim server
                abbr --add vim nvim --listen "$NVIM_LISTEN_ADDRESS"
            end
        end
    end
end

# https://github.com/mfussenegger/nvim-dap/blob/e64ebf3309154b578a03c76229ebf51c37898118/doc/dap.txt#L960
# Available log levels:
# TRACE
# DEBUG
# INFO
# WARN
# ERROR
set -gx DAP_LOG_LEVEL INFO
set -gx LSP_LOG_LEVEL INFO
set -gx CONFORM_LOG_LEVEL INFO
set -gx NEOTEST_LOG_LEVEL INFO

command -q fish; and set -gx AVAILABLE_SHELL "$(command -v fish)"; or set -gx AVAILABLE_SHELL "$(command -v bash)"
