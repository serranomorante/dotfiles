# {{ ansible_managed }}
# Common sandbox for terminal AI coding agents. The wrapper exposes the current
# working directory; this profile exposes only agent state, MCP runtime state,
# and host toolchains required by child MCP commands that inherit the sandbox.
include dev-tools-common.inc
dbus-user none

# Read-only host toolchains and helper commands.
whitelist-ro ${HOME}/.volta
whitelist-ro ${HOME}/.pyenv
whitelist-ro ${HOME}/.cargo/bin
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin
whitelist-ro ${HOME}/dotfiles/utilities
whitelist-ro ${HOME}/dotfiles/for-my-eyes-only
whitelist-ro ${HOME}/.config/git
whitelist-ro ${HOME}/.gitconfig
whitelist ${HOME}/.config/gcloud
whitelist-ro ${HOME}/data/apps/dev-tools/ai-tools

# MCPHub config and logs plus child MCP runtime state. Child MCP commands reuse
# this sandbox through fj-mcp-inherit instead of starting nested Firejail.
whitelist-ro ${HOME}/.config/mcphub
whitelist ${HOME}/.local/state/mcp-hub
whitelist ${HOME}/.local/share/mcp-hub
whitelist ${HOME}/.cache/firejail-wrapper/node
whitelist ${HOME}/.local/state/firejail-wrapper/node
whitelist ${HOME}/.local/share/firejail-wrapper/node
whitelist ${HOME}/.cache/firejail-wrapper/python
whitelist ${HOME}/.local/state/firejail-wrapper/python
whitelist ${HOME}/.local/share/firejail-wrapper/python
whitelist ${HOME}/.local/share/uv

# Profile checker support for inherited MCP sandboxes.
whitelist ${HOME}/bin/fj-profile-checker
whitelist-ro ${HOME}/.config/firejail/ai-agent-common.inc
whitelist-ro ${HOME}/.config/firejail/dev-tools-common.inc
whitelist-ro ${HOME}/.config/firejail/claude.profile
whitelist-ro ${HOME}/.config/firejail/codex.profile
whitelist-ro ${HOME}/.config/firejail/gemini.profile

# Keep sensitive host data hidden unless the launcher explicitly exposes a CWD
# or extra path that contains it.
blacklist ${HOME}/.ssh
blacklist ${HOME}/.gnupg
blacklist ${HOME}/data/secrets
blacklist ${HOME}/data/notes/foam

# AI agents and MCPHub need local HTTP plus internet access.
protocol unix,inet,inet6,netlink
