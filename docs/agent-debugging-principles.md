# Agent Debugging Principles

Prefer discovering existing runtime state before adding parameters, environment variables, caches, files, or one-off wiring.

- First inspect available channels: parent/supervisor environment, `/proc` metadata, tool APIs such as Kitty remote control, cwd/command line/window ids/user vars, and existing wrapper contracts.
- If several tools need the same value, centralize the resolver and have callers use it.
- If data seems missing, check whether it exists in another shape, such as parent pid, socket, window id, or cwd.
- Add new explicit state only after proving no stable existing source is available.
- Document reusable resolution rules near the owning workflow doc so future fixes do not add per-tool exceptions.
