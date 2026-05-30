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
# wrapper verifies this profile's filesystem rules. Keep the Ansible language
# server runtime paths visible here so it does not need nested Firejail.
whitelist-ro ${HOME}/data/apps/lang-tools/ansible-language-server/.npm
whitelist-ro ${HOME}/.config/firejail/fj-dev-nvim.profile
whitelist-ro ${HOME}/.config/firejail/dev-tools-common.inc
whitelist-ro ${HOME}/.config/firejail/dev-editor-shell-common.inc

# Sensitive host paths that child wrappers must confirm remain hidden before
# reusing this sandbox.
blacklist ${HOME}/.ssh
blacklist ${HOME}/.gnupg
blacklist ${HOME}/data/secrets
blacklist ${HOME}/data/notes/foam

# Writable reminder data consumed by the Neovim reminder helpers.
whitelist ${HOME}/.config/remind
