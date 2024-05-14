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

abbr --add config /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME"

abbr --add lazydots lazygit --git-dir="$HOME/.dotfiles/" --work-tree="$HOME"

command -q nvim; and abbr --add vim nvim

command -q volta; and set -gx SYSTEM_DEFAULT_NODE_VERSION $(volta list node | grep "default" | cut -d "@" -f 2 | cut -d " " -f 1)

set -l tmux_work_script ~/.config/tmux/scripts/work.sh
set -l tmux_config_script ~/.config/tmux/scripts/config.sh

if test -e "$tmux_work_script"; and test -x "$tmux_work_script"
    abbr --add work ~/.config/tmux/scripts/work.sh
end

if test -e "$tmux_config_script"; and test -x "$tmux_config_script"
    abbr --add conf ~/.config/tmux/scripts/config.sh
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
