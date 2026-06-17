#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities notifications dunst python
# dotfiles-test-case: notification-action-syntax
# dotfiles-test-case: notification-action-dispatch-opens-foam-block
# dotfiles-test-case: notification-action-send-dispatches-selected-action
# dotfiles-test-case: notification-action-send-caps-timeout
# dotfiles-test-case: notification-action-falls-back-to-plain-notify

# Purpose: Verify versioned notification action payloads without requiring a live Dunst session.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/notification-action"

make_fake_home() {
    local home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "${home}/bin" "${DOTFILES_TEST_TMP}/notes"
    cat >"${home}/bin/open_in_nvim" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/open-in-nvim.args"
BASH
    chmod +x "${home}/bin/open_in_nvim"
    printf '%s\n' "$home"
}

payload() {
    printf '{"schema":"dotfiles.notification-action.v1","action":"open-foam-block-section","cwd":"%s","foam-section-id":"todo-sample-agent-task"}\n' "${DOTFILES_TEST_TMP}/notes"
}

assert_arg_value() {
    local args_file="$1"
    local expected_key="$2"
    local expected_value="$3"

    awk -v key="$expected_key" -v expected="$expected_value" '
        previous == key && $0 == expected { found = 1 }
        { previous = $0 }
        END { exit found ? 0 : 1 }
    ' "$args_file"
}

write_fake_dunstify() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/dunstify" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/dunstify.args"
for arg in "$@"; do
    case "$arg" in
    dotfiles-action-v1:*,*)
        printf '%s\n' "${arg%%,*}"
        ;;
    esac
done
BASH
    chmod +x "${bin}/dunstify"
    printf '%s\n' "$bin"
}

write_failing_dunstify_with_plain_notify() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/dunstify" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/dunstify.args"
printf 'simulated dunstify failure\n' >&2
exit 1
BASH
    chmod +x "${bin}/dunstify"
    cat >"${bin}/notify-send" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/notify-send.args"
BASH
    chmod +x "${bin}/notify-send"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
notification-action-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
notification-action-dispatch-opens-foam-block)
    home=$(make_fake_home)
    HOME="$home" "$script_under_test" dispatch "$(payload)"
    [[ "$(cat "${DOTFILES_TEST_TMP}/open-in-nvim.args")" == "--cwd ${DOTFILES_TEST_TMP}/notes goto_foam_block_by_id todo-sample-agent-task" ]]
    ;;
notification-action-send-dispatches-selected-action)
    home=$(make_fake_home)
    bin=$(write_fake_dunstify)
    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" send --summary Done --body todo --label Open "$(payload)"
    rg -q -- '^-A$' "${DOTFILES_TEST_TMP}/dunstify.args"
    assert_arg_value "${DOTFILES_TEST_TMP}/dunstify.args" -t 7000
    rg -q -- '^Done$' "${DOTFILES_TEST_TMP}/dunstify.args"
    [[ "$(cat "${DOTFILES_TEST_TMP}/open-in-nvim.args")" == "--cwd ${DOTFILES_TEST_TMP}/notes goto_foam_block_by_id todo-sample-agent-task" ]]
    ;;
notification-action-send-caps-timeout)
    home=$(make_fake_home)
    bin=$(write_fake_dunstify)
    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" send --summary Done --body todo --label Open --timeout-ms 600000 "$(payload)"
    assert_arg_value "${DOTFILES_TEST_TMP}/dunstify.args" -t 7000
    ;;
notification-action-falls-back-to-plain-notify)
    home=$(make_fake_home)
    bin=$(write_failing_dunstify_with_plain_notify)
    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" send --summary Done --body todo --label Open "$(payload)"
    rg -q -- '^Done$' "${DOTFILES_TEST_TMP}/notify-send.args"
    rg -q -- '^todo$' "${DOTFILES_TEST_TMP}/notify-send.args"
    [[ ! -e "${DOTFILES_TEST_TMP}/open-in-nvim.args" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
