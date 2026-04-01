# {{ ansible_managed }}
quiet
# Minimal npm/pnpm install profile. The wrapper provides the work root and any
# explicit overrides; this profile exposes the stable host toolchains plus the
# normal cache/state locations used by npm and pnpm.
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
