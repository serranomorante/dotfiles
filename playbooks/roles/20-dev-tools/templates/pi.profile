# {{ ansible_managed }}
quiet
# Pi profile. The wrapper supplies the writable cwd; this profile keeps Pi
# config/state and shared MCP runtime visible.
include ai-agent-common.inc

whitelist ${HOME}/.pi
whitelist ${HOME}/.cache/pi
whitelist ${HOME}/.local/state/pi
whitelist ${HOME}/.local/share/pi
