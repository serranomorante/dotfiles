# {{ ansible_managed }}
quiet
# Minimal Composer install profile. The wrapper provides the work root and any
# explicit overrides; this profile exposes only scoped persistent tool state.
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
