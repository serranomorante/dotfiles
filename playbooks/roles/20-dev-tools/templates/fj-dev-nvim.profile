# {{ ansible_managed }}
quiet
# Interactive Neovim profile. Keep the shared hardening baseline and editor
# state, then expose the language runtimes Neovim commonly shells out to.
include dev-tools-common.inc
dbus-user none
include dev-editor-shell-common.inc

# Read-only language runtimes and shim locations used by Neovim tooling.
whitelist-ro ${HOME}/.volta
whitelist-ro ${HOME}/.pyenv
whitelist-ro ${HOME}/.cargo/bin

# Writable reminder data consumed by the Neovim reminder helpers.
whitelist ${HOME}/.config/remind
