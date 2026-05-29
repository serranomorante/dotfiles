#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities remind agent shell
# dotfiles-test-case: remind-run-lists-agent-command
# dotfiles-test-case: remind-run-agent-dispatches-helper
# dotfiles-test-case: remind-run-agent-rejects-invalid-id

# Purpose: Verify the Remind RUN allowlist for local agent calls.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/remind-run"

make_fake_home() {
    local home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "${home}/bin"
    cat >"${home}/bin/foam-remind-agent-run" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/agent-helper.args"
BASH
    chmod +x "${home}/bin/foam-remind-agent-run"
    printf '%s\n' "$home"
}

case "${DOTFILES_TEST_CASE:-}" in
remind-run-lists-agent-command)
    "$script_under_test" --list >"${DOTFILES_TEST_TMP}/stdout"
    rg -q '^agent <todo-id>$' "${DOTFILES_TEST_TMP}/stdout"
    ;;
remind-run-agent-dispatches-helper)
    home=$(make_fake_home)
    HOME="$home" "$script_under_test" agent todo-audio-software-deal
    [[ "$(cat "${DOTFILES_TEST_TMP}/agent-helper.args")" == "todo-audio-software-deal" ]]
    ;;
remind-run-agent-rejects-invalid-id)
    home=$(make_fake_home)
    if HOME="$home" "$script_under_test" agent 'bad/id' >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'remind-run unexpectedly accepted invalid id\n' >&2
        exit 1
    fi
    rg -q "rejected agent TODO id" "${DOTFILES_TEST_TMP}/stderr"
    [[ ! -e "${DOTFILES_TEST_TMP}/agent-helper.args" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
