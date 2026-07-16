# Neovim Ctags Links

Neovim starts the `editor-tasks-refresh-ctags` Overseer task for Kitty cwd-scoped sessions. That task resolves `utils.git_root_or_cwd()`, runs `nvim/bin/dotfiles-refresh-ctags` from that project root, generates the normal Universal Ctags `tags` file there, and appends repository-specific tags that make structural Ansible/YAML navigation work through native Vim tag commands such as `Ctrl-]`, `:tag`, `:tjump`, and `:ts`.

The wrapper keeps the existing ctags exclusions for `.git`, `node_modules`, `.mypy_cache`, generated web assets, minified bundles, and the `tags` file itself. It sorts the final merged file after appending synthetic tags so Vim's default `tagbsearch` can navigate it without `E432`.

Top-level YAML keys become tags through a Universal Ctags regex. A definition such as `arch_music_plugins_wine_prefix:` or `arch_reaper_wine_setup:` can be reached from references such as `{{ arch_music_plugins_wine_prefix }}` or `{{ arch_reaper_wine_setup.wine_prefix }}` by putting the cursor on the variable/object name and using native tag navigation.

Ansible roles become synthetic tags from directories named `roles/<role-name>`. The role tag points first to `tasks/main.yml`, then `defaults/main.yml`, then `meta/main.yml`, then the first task file if no conventional main file exists. Ansible YAML buffers add `-` to `iskeyword` so native `Ctrl-]` reads hyphenated role names such as `wine-installer-poll` as one tag name.

Ansible `register:` values in `.yml` and `.yaml` files become synthetic tags that point to the registered variable name on the registering task line. This lets `Ctrl-]` on later result-object references such as `var_dwm_remote_commit.stdout.split()[0]` jump back to `register: var_dwm_remote_commit` without a manual link comment. Register names must be plain Ansible variable identifiers made from letters, digits, and underscores.

Direct keys under Ansible `set_fact:` tasks also become synthetic tags that point to the fact key itself. A task that sets `dwm_patch_marker:` can be reached from later references such as `dotfiles_marker_name: "{{ dwm_patch_marker }}"` with native tag navigation. Only direct mapping keys under `set_fact:` are tagged, so nested keys inside fact values are ignored.

Manual links use comments named `ctags-link` placed immediately before the target line. For example, `# ctags-link: wine_prefix_setup_prefixes` before `arch_wine_prefix_setups:` creates a tag named `wine_prefix_setup_prefixes` that jumps to the `arch_wine_prefix_setups:` line. Multiple aliases can be comma-separated in one comment, such as `# ctags-link: reaper_prefix_setup, default_reaper_wine_setup`. Manual links take priority over automatically generated top-level YAML key tags with the same name, so `Ctrl-]` on a marker key such as `wine_prefix_setup_prefixes: []` can jump to the linked `arch_wine_prefix_setups:` target instead of navigating to its own line.

Prefer the simplest link source that fits the data. Use a real top-level YAML key when the target already has a meaningful symbol, rely on generated role tags when jumping to role entrypoints, and use `ctags-link` only when the desired jump name differs from the target's real symbol or when a target line has no good native name.

Do not delete existing `quicksearch` comments solely because a tag now exists. Treat ctags links as the preferred structural navigation path and keep `quicksearch` as a fallback for ad-hoc regex searches until the surrounding workflow no longer needs them.
