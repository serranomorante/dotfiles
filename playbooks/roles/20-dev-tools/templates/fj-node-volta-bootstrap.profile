# {{ ansible_managed }}
quiet
# Bootstrap profile for installing Volta before fj-node is available.
include dev-tools-common.inc
dbus-user none

whitelist ${HOME}/.volta
whitelist ${HOME}/.cache/firejail-wrapper/node
whitelist ${HOME}/.local/state/firejail-wrapper/node
whitelist-ro ${HOME}/bin
