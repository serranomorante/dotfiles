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

# Child language servers spawned by Neovim inherit this sandbox only when their
# wrapper can verify the fj-dev-nvim private marker. Keep the Ansible language
# server runtime paths visible here so it does not need a nested Firejail.
whitelist-ro ${HOME}/data/apps/lang-tools/ansible-language-server/.npm

# Writable reminder data consumed by the Neovim reminder helpers.
whitelist ${HOME}/.config/remind
