# Agent Debugging Principles

This repository favors discovering existing runtime state before adding new parameters, environment variables, cache entries, or case-specific wiring.

## Prefer Discovery Before Injection

When a script or tool needs a value, first check whether the running system already exposes that information through an existing channel. Examples include:

- process environment inherited by a parent or supervisor
- process metadata under `/proc`
- tool-specific state APIs such as Kitty remote control
- current working directories, command lines, window ids, and user variables
- existing wrapper contracts documented in this repository

Only add a new parameter, environment variable, state file, or cache key after checking those sources and finding that the information is not already available with a stable enough identity.

## Keep Contracts Central

If several tools need the same value, prefer one shared resolution contract over injecting the value separately at every call site. For example, `open_in_nvim` resolves the Neovim server from a valid cwd-derived `KITTY_LISTEN_ON`, then from `KITTY_PID`, then from the caller cwd. Callers such as lazygit and nnn should normally rely on that resolver instead of each passing their own derived server path.

## Investigate Shape Mismatches

If the needed information appears missing, verify whether it exists in a different shape before adding another explicit path. A child process may not inherit the exact variable expected, but it may expose a parent pid, socket, window id, or cwd that leads back to the same information.

Document new reusable resolution rules near the owning workflow doc so future changes can build on the same contract instead of adding per-tool exceptions.
