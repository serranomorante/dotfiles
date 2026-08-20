#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: firejail static fast
# dotfiles-test-case: firejail-dev-tool-profiles-avoid-broad-xdg
# dotfiles-test-case: firejail-dev-nvim-avoids-global-nvim-state
# dotfiles-test-case: firejail-promnesia-exposes-stow-target
# dotfiles-test-case: firejail-promnesia-exposes-agent-conversation-dirs
# dotfiles-test-case: firejail-ai-agent-profiles-avoid-broad-xdg
# dotfiles-test-case: firejail-ai-agent-mcp-uses-inherited-sandbox
# dotfiles-test-case: firejail-ai-agent-runtime-launchers-use-wrappers
# dotfiles-test-case: firejail-ai-agent-orchestration-paths-visible
# dotfiles-test-case: firejail-ai-agent-controls-foam-notes-exposure
# dotfiles-test-case: firejail-ai-agent-stow-targets-visible
# dotfiles-test-case: firejail-ai-agent-keeps-host-tmp

# Purpose: Static guardrails for dev-tool Firejail profile path exposure.

root=${DOTFILES_TEST_ROOT}

case "${DOTFILES_TEST_CASE:-}" in
firejail-dev-tool-profiles-avoid-broad-xdg)
    for profile in \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node-ansible.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-node-volta-bootstrap.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-php.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-php-ansible.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/fj-py.profile"; do
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.cache([[:space:]]|$)' "$profile"; then
            printf 'broad cache whitelist in %s\n' "$profile" >&2
            exit 1
        fi
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.local/(state|share)([[:space:]]|$)' "$profile"; then
            printf 'broad local state/share whitelist in %s\n' "$profile" >&2
            exit 1
        fi
    done
    ;;
firejail-dev-nvim-avoids-global-nvim-state)
    profile="$root/playbooks/roles/20-dev-tools/templates/dev-editor-shell-common.inc"
    for path in \
        '${HOME}/.cache/nvim' \
        '${HOME}/.local/state/nvim' \
        '${HOME}/.local/share/nvim'; do
        if grep -Fqx "whitelist ${path}" "$profile"; then
            printf 'global writable Neovim state whitelist remains: %s\n' "$path" >&2
            exit 1
        fi
    done
    ;;
firejail-promnesia-exposes-stow-target)
    profile="$root/playbooks/roles/20-dev-tools/templates/fj-py-promnesia.profile"
    for path in \
        'whitelist-ro ${HOME}/dotfiles/PKM/dot-config/my' \
        'whitelist-ro ${HOME}/dotfiles/PKM/dot-config/promnesia'; do
        if ! grep -Fqx "$path" "$profile"; then
            printf 'Promnesia profile does not expose stowed config target: %s\n' "$path" >&2
            exit 1
        fi
    done
    ;;
firejail-promnesia-exposes-agent-conversation-dirs)
    profile="$root/playbooks/roles/20-dev-tools/templates/fj-py-promnesia.profile"
    for path in \
        'whitelist-ro ${HOME}/.claude/projects' \
        'whitelist-ro ${HOME}/.codex/sessions' \
        'whitelist-ro ${HOME}/.gemini/tmp' \
        'whitelist-ro ${HOME}/.local/share/opencode'; do
        if ! grep -Fqx "$path" "$profile"; then
            printf 'Promnesia profile does not expose agent conversation dir: %s\n' "$path" >&2
            exit 1
        fi
    done
    ;;
firejail-ai-agent-profiles-avoid-broad-xdg)
    for profile in \
        "$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc" \
        "$root/playbooks/roles/20-dev-tools/templates/claude.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/codex.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/gemini.profile" \
        "$root/playbooks/roles/20-dev-tools/templates/opencode.profile"; do
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.cache([[:space:]]|$)' "$profile"; then
            printf 'broad cache whitelist in %s\n' "$profile" >&2
            exit 1
        fi
        if grep -Eq '^[[:space:]]*whitelist[[:space:]]+\$\{HOME\}/\.local/(state|share)([[:space:]]|$)' "$profile"; then
            printf 'broad local state/share whitelist in %s\n' "$profile" >&2
            exit 1
        fi
    done
    ;;
firejail-ai-agent-mcp-uses-inherited-sandbox)
    profile="$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc"
    servers="$root/playbooks/roles/20-dev-tools/templates/mcphub_servers.json"
    wrapper="$root/playbooks/roles/20-dev-tools/files/fj-mcp-inherit"
    for path in \
        'whitelist ${HOME}/bin/fj-profile-checker' \
        'whitelist-ro ${HOME}/.local/share/firejail-wrapper/ai-agent-profiles'; do
        if ! grep -Fqx "$path" "$profile"; then
            printf 'AI agent profile does not expose inherited sandbox checker path: %s\n' "$path" >&2
            exit 1
        fi
    done
    if ! grep -Fq '"command": "{{ node_user_bin_dir }}/fj-mcp-inherit"' "$servers"; then
        printf 'MCPHub servers do not use fj-mcp-inherit\n' >&2
        exit 1
    fi
    if ! grep -Fq 'if is_inside_firejail; then' "$wrapper"; then
        printf 'fj-mcp-inherit does not detect inherited Firejail\n' >&2
        exit 1
    fi
    ;;
firejail-ai-agent-runtime-launchers-use-wrappers)
    nvim_agent_sessions="$root/nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/agent_sessions.lua"
    local_execution="$root/utilities/bin/agent-local-execution"
    davinci_tasks="$root/playbooks/roles/10-system-tools/tasks/220-setup-video-tools.archlinux.yml"
    for expected in \
        'executable = "fj-codex"' \
        'executable = "fj-claude"' \
        'executable = "fj-gemini"' \
        'mcp_executable = "gemini-mcp"'; do
        if ! grep -Fq "$expected" "$nvim_agent_sessions"; then
            printf 'Neovim agent launcher is missing wrapper config: %s\n' "$expected" >&2
            exit 1
        fi
    done
    for expected in \
        'f"fj-{agent}"' \
        'launch_prefix'; do
        if ! grep -Fq "$expected" "$local_execution"; then
            printf 'agent-local-execution is missing dynamic fj-* wrapper construction: %s\n' "$expected" >&2
            exit 1
        fi
    done
    if ! grep -Fq '/bin/fj-claude' "$davinci_tasks"; then
        printf 'DaVinci Claude runtime task does not use fj-claude\n' >&2
        exit 1
    fi
    ;;
firejail-ai-agent-orchestration-paths-visible)
    profile="$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc"
    wrapper="$root/playbooks/roles/20-dev-tools/files/fj-ai-agent"
    for path in \
        'whitelist-ro ${HOME}/dotfiles/utilities' \
        'whitelist-ro ${HOME}/dotfiles/for-my-eyes-only' \
        'whitelist ${HOME}/.config/gcloud' \
        'whitelist-ro ${HOME}/data/apps/dev-tools/firebase-{{ firebase_cli_version }}' \
        'whitelist ${HOME}/.config/configstore' \
        'whitelist ${HOME}/.cache/firebase'; do
        if ! grep -Fqx "$path" "$profile"; then
            printf 'AI agent profile does not expose required runtime path: %s\n' "$path" >&2
            exit 1
        fi
    done
    for expected in \
        '"$real_home/.config/gcloud"' \
        '"$real_home/.config/configstore"' \
        '"$real_home/.cache/firebase"' \
        'work_root=$(resolve_default_work_root)' \
        'git -C "$cwd" rev-parse --show-toplevel' \
        'NVIM' \
        'AGENT_TASKS_NVIM' \
        'tmux_socket_dir="/tmp/tmux-$(id -u)"' \
        'append_optional_path rw "$tmux_socket_dir"' \
        '[[ -d "$real_home/dotfiles" ]] && add_rw_path "$real_home/dotfiles"' \
        '[[ -d "$real_home/data/work/cf" ]] && add_rw_path "$real_home/data/work/cf"'; do
        if ! grep -Fq "$expected" "$wrapper"; then
            printf 'AI agent wrapper is missing orchestration access: %s\n' "$expected" >&2
            exit 1
        fi
    done
    ;;
firejail-ai-agent-controls-foam-notes-exposure)
    profile="$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc"
    wrapper="$root/playbooks/roles/20-dev-tools/files/fj-ai-agent"
    if grep -Fq 'blacklist ${HOME}/data/notes/foam' "$profile"; then
        printf 'AI agent profile must not statically blacklist the foam notes tree\n' >&2
        exit 1
    fi
    for expected in \
        'agent_notes_dir=' \
        'agents/$agent' \
        'mkdir -p "$agent_notes_dir"' \
        'add_rw_path "$agent_notes_dir"'; do
        if ! grep -Fq "$expected" "$wrapper"; then
            printf 'AI agent wrapper is missing agent notes dir exposure: %s\n' "$expected" >&2
            exit 1
        fi
    done
    # Whitelisting the agent notes dir alone must hide the rest of the foam
    # tree: Firejail mounts a tmpfs over $HOME (the whitelist top directory)
    # and only bind-mounts whitelisted paths back in, so no per-sibling
    # blacklist logic or foam-aware flags should be needed in the wrapper.
    for absent in \
        'is_under_foam_notes' \
        'expose_foam' \
        'foam_profile_blacklist' \
        'FJ_AI_AGENT_FOAM_NOTES_ROOT' \
        '--blacklist=$foam_notes_root' \
        '--noblacklist='; do
        if grep -Fq -- "$absent" "$wrapper"; then
            printf 'AI agent wrapper must rely on the agent notes dir whitelist only: %s\n' "$absent" >&2
            exit 1
        fi
    done
    ;;
firejail-ai-agent-stow-targets-visible)
    profile="$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc"
    node_tasks="$root/playbooks/roles/20-dev-tools/tasks/10-setup-node.archlinux.yml"
    stow_wrapper_tasks="$root/playbooks/roles/10-system-tools/tasks/30-setup-dotfiles-wrapper.yml"
    stow_wrapper="$root/playbooks/roles/10-system-tools/templates/dotfiles-stow"
    generator="$root/playbooks/roles/10-system-tools/templates/dotfiles-ai-agent-stow-targets"
    for expected in \
        'include ai-agent-stow-targets.inc' \
        'whitelist-ro ${HOME}/.local/share/firejail-wrapper/ai-agent-profiles'; do
        if ! grep -Fqx "$expected" "$profile"; then
            printf 'AI agent profile is missing Stow target include support: %s\n' "$expected" >&2
            exit 1
        fi
    done
    for expected in \
        'ai-agent-stow-targets.inc' \
        'dotfiles-ai-agent-stow-targets'; do
        if ! grep -Fq "$expected" "$node_tasks"; then
            printf 'Node setup does not maintain AI agent Stow target includes: %s\n' "$expected" >&2
            exit 1
        fi
    done
    if ! grep -Fq 'dotfiles-ai-agent-stow-targets' "$stow_wrapper_tasks"; then
        printf 'Dotfiles wrapper setup does not install the AI agent Stow target generator\n' >&2
        exit 1
    fi
    if ! grep -Fq 'refresh_ai_agent_stow_targets' "$stow_wrapper"; then
        printf 'dotfiles-stow does not refresh AI agent Stow target includes\n' >&2
        exit 1
    fi
    for expected in \
        '--simulate' \
        '--verbose=2' \
        '[[ -e "$target_path" || -L "$target_path" ]] || continue' \
        'readlink -f "$target_path"' \
        '"$dotfiles_stow_dir"/*) ;;' \
        '.mypy_cache | .mypy_cache/*' \
        '.config/firejail | .config/firejail/*' \
        'snapshot_output_path='; do
        if ! grep -Fq -- "$expected" "$generator"; then
            printf 'AI agent Stow target generator is missing expected guard: %s\n' "$expected" >&2
            exit 1
        fi
    done
    ;;
firejail-ai-agent-keeps-host-tmp)
    agent_profile="$root/playbooks/roles/20-dev-tools/templates/ai-agent-common.inc"
    baseline="$root/playbooks/roles/20-dev-tools/templates/dev-tools-common.inc"
    if ! grep -Fqx 'ignore private-tmp' "$agent_profile"; then
        printf 'AI agent profile must keep the real host /tmp for agent/host handoffs\n' >&2
        exit 1
    fi
    if ! grep -Fqx 'private-tmp' "$baseline"; then
        printf 'dev-tools-common.inc must keep private-tmp for generic wrappers\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
