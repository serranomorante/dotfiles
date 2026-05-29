# {{ ansible_managed }}
quiet
# Generic Node profile: the wrapper injects the project root and any extra
# user-specified paths. Keep persistent tool state scoped so untrusted package
# code cannot read unrelated XDG cache/state/data content.
include dev-tools-common.inc
dbus-user none

# Read-only host toolchains and shim locations.
whitelist-ro ${HOME}/.volta
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin

# Writable host cache and state used by node tooling.
whitelist ${HOME}/.cache/firejail-wrapper/node
whitelist ${HOME}/.local/state/firejail-wrapper/node
whitelist ${HOME}/.local/share/firejail-wrapper/node
