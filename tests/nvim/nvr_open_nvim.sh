#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim scripts editor-scheme
# dotfiles-test-case: nvr-open-nvim-routes-agent-conversation-link
# dotfiles-test-case: nvr-open-nvim-passes-through-regular-editor-link

# Purpose: Verify the editor:// scheme entry point routes agent conversation
# links to open_in_nvim and keeps plain file links on the kitty-open-in-editor
# path.

script_under_test="${DOTFILES_TEST_ROOT}/nvim/bin/nvr_open_nvim.sh"

fake_bin() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/open_in_nvim" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/open_in_nvim.args"
BASH
    cat >"${bin}/kitty-open-in-editor" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/kitty-open-in-editor.args"
BASH
    chmod +x "${bin}/open_in_nvim" "${bin}/kitty-open-in-editor"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
nvr-open-nvim-routes-agent-conversation-link)
    bin=$(fake_bin)

    PATH="$bin:/usr/bin:/bin" "$script_under_test" "editor:///agent_conversation/home/aaaa/dotfiles/playbooks/019ec503-1d4c"

    rg -q -- '^--cwd /home/aaaa/dotfiles/playbooks agent_conversation 019ec503-1d4c$' "${DOTFILES_TEST_TMP}/open_in_nvim.args"
    if [[ -e "${DOTFILES_TEST_TMP}/kitty-open-in-editor.args" ]]; then
        printf 'agent conversation link must not reach kitty-open-in-editor\n' >&2
        exit 1
    fi
    ;;
nvr-open-nvim-passes-through-regular-editor-link)
    bin=$(fake_bin)

    PATH="$bin:/usr/bin:/bin" "$script_under_test" "editor:///home/aaaa/data/notes/foam/foo.md:12"

    rg -q -- '^/home/aaaa/data/notes/foam/foo.md:12$' "${DOTFILES_TEST_TMP}/kitty-open-in-editor.args"
    if [[ -e "${DOTFILES_TEST_TMP}/open_in_nvim.args" ]]; then
        printf 'plain editor link must not reach open_in_nvim\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
