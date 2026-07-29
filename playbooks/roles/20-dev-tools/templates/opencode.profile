# {{ ansible_managed }}
quiet
# OpenCode profile. The wrapper supplies the writable cwd; this profile keeps
# OpenCode config/state and shared MCP runtime visible.
include ai-agent-common.inc

whitelist ${HOME}/.config/opencode
whitelist ${HOME}/.cache/opencode
whitelist ${HOME}/.local/state/opencode
whitelist ${HOME}/.local/share/opencode
