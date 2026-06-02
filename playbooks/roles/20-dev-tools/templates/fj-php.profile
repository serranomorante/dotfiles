# {{ ansible_managed }}
quiet
# Generic PHP profile: the wrapper injects the project root and any extra
# user-specified paths. Keep persistent Composer state scoped so untrusted
# package code cannot read unrelated Composer config, auth, cache, or XDG state.
include dev-tools-common.inc
dbus-user none

# Read-only host shim locations.
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin
whitelist-ro ${HOME}/dotfiles/utilities/bin

# Writable host cache and state used by PHP and Composer tooling.
whitelist ${HOME}/.cache/firejail-wrapper/php
whitelist ${HOME}/.local/state/firejail-wrapper/php
whitelist ${HOME}/.local/share/firejail-wrapper/php
