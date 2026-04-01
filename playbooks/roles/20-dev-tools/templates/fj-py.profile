# {{ ansible_managed }}
quiet
# Generic Python profile: the wrapper injects the project root and any extra
# user-specified paths. This profile exposes the stable host runtimes plus the
# normal cache/state locations used by Python, pip, and uv.
include dev-tools-common.inc
dbus-user none

# Read-only host runtimes and shim locations.
whitelist-ro ${HOME}/.pyenv
whitelist-ro ${HOME}/.cargo/bin
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin

# Writable host cache and state used by python tooling.
whitelist ${HOME}/.cache
whitelist ${HOME}/.local/state
whitelist ${HOME}/.local/share
