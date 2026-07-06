# Shared session environment for interactive shells, scripts, and systemd --user.
# Keep this file free of aliases, prompt setup, terminal I/O, and slow hooks.

dotfiles_path_remove() {
    local dir="$1"
    local old_ifs="$IFS"
    local part
    local new_path=

    [ -n "$dir" ] || return 0

    IFS=:
    for part in ${PATH:-}; do
        [ "$part" = "$dir" ] && continue
        if [ -n "$new_path" ]; then
            new_path="$new_path:$part"
        else
            new_path="$part"
        fi
    done
    IFS="$old_ifs"

    PATH="$new_path"
}

dotfiles_path_prepend() {
    local dir="$1"
    [ -n "$dir" ] || return 0
    dotfiles_path_remove "$dir"
    PATH="$dir${PATH:+:$PATH}"
}

dotfiles_path_append() {
    local dir="$1"
    [ -n "$dir" ] || return 0
    dotfiles_path_remove "$dir"
    PATH="${PATH:+$PATH:}$dir"
}

export DOTFILES_SESSION_ENV_KEYS="PATH VOLTA_HOME PYENV_ROOT SSH_AUTH_SOCK FONTCONFIG_PATH COLORTERM EDITOR SYSTEMD_PAGER FZF_DEFAULT_COMMAND FZF_DEFAULT_OPTS RIPGREP_CONFIG_PATH WIREPLUMBER_DEBUG DAP_LOG_LEVEL LSP_LOG_LEVEL CONFORM_LOG_LEVEL NEOTEST_LOG_LEVEL DJANGO_READ_DOT_ENV_FILE"

DOTFILES_SYSTEM_PATH_DEFAULT="/usr/local/sbin:/usr/local/bin:/usr/bin:/opt/cuda/bin:/var/lib/flatpak/exports/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
PATH="${DOTFILES_SYSTEM_PATH:-$DOTFILES_SYSTEM_PATH_DEFAULT}"
unset DOTFILES_SYSTEM_PATH_DEFAULT

brew_ubuntu_path=/home/linuxbrew/.linuxbrew/bin/brew
if [ -x "$brew_ubuntu_path" ]; then
    eval "$("$brew_ubuntu_path" shellenv)"
fi
unset brew_ubuntu_path

dotfiles_path_prepend "$HOME/bin"
dotfiles_path_prepend "$HOME/.local/bin"
dotfiles_path_prepend "$HOME/.local/share/yabridge"
dotfiles_path_prepend "$HOME/.local/kitty.app/bin"
dotfiles_path_prepend "/usr/lib/python3.11/site-packages"
dotfiles_path_append "${GOBIN:-}"
dotfiles_path_append "${GOPATH:-$HOME/go}/bin"

export FONTCONFIG_PATH=/etc/fonts
export COLORTERM=truecolor
export EDITOR=nvim
export SYSTEMD_PAGER=""
export FZF_DEFAULT_COMMAND="fd --type f"
export FZF_DEFAULT_OPTS="--layout=reverse --border"
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
export WIREPLUMBER_DEBUG=0
export DAP_LOG_LEVEL=INFO
export LSP_LOG_LEVEL=INFO
export CONFORM_LOG_LEVEL=INFO
export NEOTEST_LOG_LEVEL=INFO
export DJANGO_READ_DOT_ENV_FILE=True

## BEGIN ANSIBLE MANAGED BLOCK - SETUP NODE
export VOLTA_HOME="$HOME/.volta"
dotfiles_path_prepend "$VOLTA_HOME/bin"
dotfiles_path_prepend "$VOLTA_HOME/tools/image/node/22.23.1/bin" # version is replaced by ansible
## END ANSIBLE MANAGED BLOCK - SETUP NODE
## BEGIN ANSIBLE MANAGED BLOCK - SETUP PYTHON
export PYENV_ROOT="$HOME/.pyenv"
dotfiles_path_prepend "/usr/bin/pyenv"
dotfiles_path_prepend "$PYENV_ROOT/shims"
## END ANSIBLE MANAGED BLOCK - SETUP PYTHON
## BEGIN ANSIBLE MANAGED BLOCK - SETUP ENCRYPTION
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
fi
## END ANSIBLE MANAGED BLOCK - SETUP ENCRYPTION

dotfiles_path_prepend "$HOME/bin"
dotfiles_path_append "$HOME/.local/share/yabridge"
export PATH
