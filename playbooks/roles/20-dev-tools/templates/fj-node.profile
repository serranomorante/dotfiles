# {{ ansible_managed }}
quiet
# Generic Node profile: the wrapper injects the project root and any extra
# user-specified paths. This profile exposes the stable host toolchains plus
# the normal cache/state locations used by npm and pnpm.
include dev-tools-common.inc
dbus-user none

# Read-only host toolchains and shim locations.
whitelist-ro ${HOME}/.volta
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin

# Writable host cache and state used by node tooling.
whitelist ${HOME}/.npm
whitelist ${HOME}/.cache
whitelist ${HOME}/.local/state
whitelist ${HOME}/.local/share
