# {{ ansible_managed }}
# Common sandbox for terminal AI coding agents. The wrapper exposes the current
# working directory; this profile exposes only agent state, MCP runtime state,
# and host toolchains required by child MCP commands that inherit the sandbox.
include dev-tools-common.inc
dbus-user none

# Generated from active Stow targets so agents can resolve ~/.config, ~/bin,
# and other dotfile symlinks without exposing unrelated $HOME content.
include ai-agent-stow-targets.inc

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
whitelist-ro ${HOME}/.cache/ms-playwright
whitelist ${HOME}/.config/gcloud
whitelist-ro ${HOME}/data/apps/dev-tools/ai-tools

# Firebase CLI: ${HOME}/bin/firebase is a symlink, so the pinned standalone
# binary needs its own read-only entry. Hosting deploys also need the writable
# login/token store in configstore and the CLI's own cache directory.
whitelist-ro ${HOME}/data/apps/dev-tools/firebase-{{ firebase_cli_version }}
whitelist ${HOME}/.config/configstore
whitelist ${HOME}/.cache/firebase

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
whitelist-ro ${HOME}/.local/share/firejail-wrapper/ai-agent-profiles

# Keep sensitive host data hidden unless the launcher explicitly exposes a CWD
# or extra path that contains it. The private foam notes tree needs no static
# blacklist here: fj-ai-agent whitelists only the current agent's own notes dir,
# and Firejail mounts a tmpfs over $HOME (the whitelist top directory) with only
# the whitelisted paths bound back in, so the rest of the tree stays hidden.
blacklist ${HOME}/.ssh
blacklist ${HOME}/.gnupg
blacklist ${HOME}/data/secrets

# AI agents and MCPHub need local HTTP plus internet access.
protocol unix,inet,inet6,netlink
