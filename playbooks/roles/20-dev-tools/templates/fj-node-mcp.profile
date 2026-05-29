# {{ ansible_managed }}
quiet
# Node MCP servers use stdio plus service-specific network access selected by
# fj-node. Keep D-Bus hidden; API tokens are forwarded explicitly per server.
include fj-node.profile
