# {{ ansible_managed }}
quiet
# Claude Code profile. More restrictive than Firejail's upstream Claude profile
# because it whitelists only Claude/MCP state plus the wrapper-supplied cwd.
include ai-agent-common.inc

whitelist ${HOME}/.claude
whitelist ${HOME}/.claude.json
whitelist ${HOME}/.cache/claude-cli-nodejs
whitelist ${HOME}/.local/state/claude
whitelist ${HOME}/.local/share/claude
