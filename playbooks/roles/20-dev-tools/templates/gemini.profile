# {{ ansible_managed }}
quiet
# Gemini CLI profile. The wrapper supplies the writable cwd; this profile keeps
# Gemini config/state and shared MCP runtime visible.
include ai-agent-common.inc

whitelist ${HOME}/.gemini
whitelist ${HOME}/.cache/gemini
whitelist ${HOME}/.local/state/gemini
whitelist ${HOME}/.local/share/gemini
