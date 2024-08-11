if status is-interactive
    # Commands to run in interactive sessions can go here
    set -g fish_greeting ""

    # Set vi key bindings
    set fish_key_bindings fish_vi_key_bindings
    # Emulates vim's cursor shape behavior
    # Set the normal and visual mode cursors to a block
    set fish_cursor_default block blink
    # https://github.com/fish-shell/fish-shell/issues/5894
    set -g fish_escape_delay_ms 10

    # See https://github.com/pyenv/pyenv#set-up-your-shell-environment-for-pyenv
    command -q pyenv; and pyenv init - | source

    # https://github.com/ajeetdsouza/zoxide?tab=readme-ov-file#installation
    command -q zoxide; and zoxide init fish | source

    # https://github.com/direnv/direnv/blob/master/docs/hook.md#fish
    command -q direnv; and direnv hook fish | source
end
