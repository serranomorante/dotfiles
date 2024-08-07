#
# ~/.bashrc
#

# All this file will be source by bass fish plugin in config.fish
# ---------------------------------------------------------------

# The line below is commented because it wasn't working with
# bass fish plugin.

# If not running interactively, don't do anything
# [[ $- != *i* ]] && return

# alias ls='ls --color=auto'
#
brew_ubuntu_path=/home/linuxbrew/.linuxbrew/bin/brew

if [ -x "$brew_ubuntu_path" ]; then
    eval "$($brew_ubuntu_path shellenv)"
fi


if [ -x "$(command -v eza)" ]; then
    alias ls='eza -1 -a -h --git --sort modified -l --icons always --color always'
fi

alias grep='grep --color=auto'

# Clear a terminal screen for real
# https://stackoverflow.com/a/5367075
alias cls='printf "\033c"'

# path env variables
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
export PATH="$HOME/bin:$PATH"
# This fixes poetry not being found
export PATH="$HOME/.local/bin:$PATH"
# Add pynvim to path
export PATH="/usr/lib/python3.11/site-packages:$PATH"
export FONTCONFIG_PATH=/etc/fonts
# For go packages
if [ -x "$(command -v go)" ]; then
    export PATH="$PATH:$(go env GOBIN):$(go env GOPATH)/bin"
fi

# system env variables
export SYSTEMD_PAGER=""
# https://wiki.archlinux.org/title/Neovim#Use_as_a_pager
# export PAGER="nvimpager"

# fzf use df instead of find
export FZF_DEFAULT_COMMAND="fd --type f"
export FZF_DEFAULT_OPTS="--layout=reverse --border"

export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Wireplumber logging
# 0. critical warnings and fatal errors (C & E in the log)
# 1. warnings (W)
# 2. normal messages (M)
# 3. informational messages (I)
# 4. debug messages (D)
# 5. trace messages (T)
export WIREPLUMBER_DEBUG=3

# Add abbreviation for vim
if command -v nvim &> /dev/null; then
    alias vim='nvim'
fi

if command -v nvim &> /dev/null && command -v tmux &> /dev/null && [ -n "$TMUX" ]; then
    NVIM_LISTEN_ADDRESS=$(tmux show-environment NVIM_LISTEN_ADDRESS | sed "s:^.*=::")
    if [ -n "$NVIM_LISTEN_ADDRESS" ]; then
        if command -v nvr &> /dev/null; then
            nvr --nostart -s --servername "$NVIM_LISTEN_ADDRESS"
            if [ $? -eq 0 ]; then
                alias vim='nvim --remote-ui --server "$NVIM_LISTEN_ADDRESS"'
            else
                alias vim='nvim --listen "$NVIM_LISTEN_ADDRESS"'
            fi
        fi
    fi
fi

if [ -x "$(command -v volta)" ]; then
    export SYSTEM_DEFAULT_NODE_VERSION=$(volta list node | grep "default" | cut -d "@" -f 2 | cut -d " " -f 1)
fi

# https://github.com/mfussenegger/nvim-dap/blob/e64ebf3309154b578a03c76229ebf51c37898118/doc/dap.txt#L960
# Available log levels:
# TRACE
# DEBUG
# INFO
# WARN
# ERROR
export DAP_LOG_LEVEL=INFO
export LSP_LOG_LEVEL=INFO
export CONFORM_LOG_LEVEL=INFO
export NEOTEST_LOG_LEVEL=INFO

if [ -x "$(command -v fish)" ]; then
    export AVAILABLE_SHELL="$(command -v fish)"
else
    export AVAILABLE_SHELL="$(command -v bash)"
fi
