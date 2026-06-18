# Update Diff Capture

Ansible-managed package updates that should leave an inspectable diff should go through the explicit `update-diff-capture` role instead of direct package-manager tasks. The role is intentionally opt-in per ecosystem so package updates remain visible at the callsite and helper scripts do not become hidden wrappers around package managers.

New non-Arch package installs or updates should use this capture path by default whenever the ecosystem can expose a useful before/after artifact. This applies to npm globals, pip virtualenv packages, uv tools, LuaRocks packages, and Git checkouts used as installed tools or source-built packages, including pinned Git refs and floating refs such as `HEAD`, `main`, or `master`. Arch official packages and AUR installs are the standing exceptions. Current explicit non-capture exceptions are dotfiles self-checkouts, `davinci-resolve-checker`, Firebase's `https://firebase.tools/bin/linux/latest` binary, selected private upstream installers, and selected private mutable image tags.

The role's internal task names should keep Ansible output readable during broad playbook runs: include the capture scope in npm/pip/git task names, keep the original callsite as the visible workflow owner, and install the shared helper scripts only once per playbook run through `update_diff_capture_helpers_installed`.

Captured updates live under `~/.local/state/dotfiles/update-diffs/runs/`. Each captured item stores a `manifest.json`, a `summary.md`, an optional `diff.patch`, and, when a real before/after content diff is available, a small Git repository with commits that can be opened through Diffview.

Use `update-diffs list` to list captured update manifests and `update-diffs open` to open the latest captured diff in Neovim Diffview. `update-diffs open <path>` accepts a manifest path, item directory, run directory, or capture repo path.

For npm packages, call `include_role: name=update-diff-capture tasks_from=npm` with `update_diff_npm_prefix`, `update_diff_npm_packages`, `update_diff_npm_node_version`, and `update_diff_npm_executable`. The role observes installed versions before and after the real `community.general.npm` task, so it can capture unpinned packages when Ansible actually installs or updates them. Versioned packages still record `.ansible-package-<name>-<version>` markers for auditability.

For pip packages, call `include_role: name=update-diff-capture tasks_from=pip` with `update_diff_pip_venv`, `update_diff_pip_packages`, and `update_diff_pip_executable`; pass `update_diff_pip_environment` for extra environment such as `PYENV_VERSION`, and `update_diff_pip_state` when the whole package list should use a state such as `latest`. Pip capture observes installed versions before and after the real `ansible.builtin.pip` task, so it can capture unpinned packages when Ansible actually installs or updates them. Use `lookup_name` for install specs that are not importable package names, such as local paths or `git+https://...` URLs.

For uv tools, call `include_role: name=update-diff-capture tasks_from=uv-tool` with `update_diff_uv_tool_dir`, `update_diff_uv_bin_dir`, `update_diff_uv_project_dir`, `update_diff_uv_firejail_executable`, and `update_diff_uv_tools`. The backend is only for `uv tool install` packages backed by PyPI artifacts; do not use it for `uv venv` or project builds, which are installation/build state rather than local-vs-upstream package source diffs.

For LuaRocks packages, call `include_role: name=update-diff-capture tasks_from=luarocks` with `update_diff_luarocks_packages` and `update_diff_luarocks_executable`; set `update_diff_luarocks_become: true` for global/system installs. The backend observes installed rock versions before and after `luarocks install` and captures source snapshots with `luarocks unpack` when the installed version changes.

Renovate proposes changes to selected pinned versions through the root `renovate.json`; accepted changes are then installed by Ansible and captured here where the ecosystem supports a content diff. Unpinned pip packages are captured only when the Ansible task causes the installed version to change; `state: present` will not normally upgrade an already-installed package, while `state: latest` can.

For Git checkouts, call `include_role: name=update-diff-capture tasks_from=git` with `update_diff_git_repo`, `update_diff_git_dest`, and `update_diff_git_version`, plus optional `update_diff_git_depth`, `update_diff_git_force`, `update_diff_git_recursive`, and `update_diff_git_single_branch`. The role captures `old_head..new_head` before running `ansible.builtin.git`, which is important for force/depth checkouts that can replace the local worktree.

Arch official packages and AUR installs are intentionally outside this role for now. AUR review and upstream VCS review remain owned by `aur-review`, while Ansible installs only already-published local AUR packages from `[aur-local]`.

Docker images that track mutable tags such as `latest` should be treated as a future `metadata-only` capture target rather than a source diff target unless the image labels expose a useful source revision.

Do not use Ansible callback plugins or action-plugin interception for this workflow. Callback plugins cannot reliably capture pre-update artifacts, and action-plugin interception hides package-manager behavior in a way that makes update provenance harder to audit.
