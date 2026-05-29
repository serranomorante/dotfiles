# {{ ansible_managed }}
quiet
# Minimal npm/pnpm install profile. The wrapper provides the work root and any
# explicit overrides; this profile exposes only scoped persistent tool state.
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
