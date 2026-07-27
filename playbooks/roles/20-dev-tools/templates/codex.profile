# {{ ansible_managed }}
quiet
# Codex profile. The wrapper supplies the writable cwd; this profile keeps Codex
# config/state and shared MCP runtime visible.
include ai-agent-common.inc

whitelist ${HOME}/.codex
whitelist ${HOME}/.cache/codex
whitelist ${HOME}/.local/state/codex
whitelist ${HOME}/.local/share/codex
