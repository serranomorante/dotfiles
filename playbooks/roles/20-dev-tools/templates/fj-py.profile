# {{ ansible_managed }}
quiet
# Generic Python profile: the wrapper injects the project root and any extra
# user-specified paths. Keep persistent tool state scoped so untrusted package
# code cannot read unrelated XDG cache/state/data content.
include dev-tools-common.inc
dbus-user none

# Read-only host runtimes and shim locations.
whitelist-ro ${HOME}/.pyenv
whitelist-ro ${HOME}/.cargo/bin
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin

# Writable host cache and state used by python tooling.
whitelist ${HOME}/.cache/firejail-wrapper/python
whitelist ${HOME}/.local/state/firejail-wrapper/python
whitelist ${HOME}/.local/share/firejail-wrapper/python
whitelist ${HOME}/.local/share/uv
