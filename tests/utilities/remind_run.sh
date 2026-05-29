#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities remind agent shell
# dotfiles-test-case: remind-run-lists-agent-command
# dotfiles-test-case: remind-run-agent-queues-helper
# dotfiles-test-case: remind-run-dotfiles-health-queues-helper
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
    cat >"${home}/bin/dotfiles-health" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/dotfiles-health.args"
BASH
    chmod +x "${home}/bin/dotfiles-health"
    printf '%s\n' "$home"
}

write_fake_systemd_run() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/systemd-run" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/systemd-run.args"
BASH
    chmod +x "${bin}/systemd-run"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
remind-run-lists-agent-command)
    "$script_under_test" --list >"${DOTFILES_TEST_TMP}/stdout"
    rg -q '^agent <todo-id>$' "${DOTFILES_TEST_TMP}/stdout"
    ;;
remind-run-agent-queues-helper)
    home=$(make_fake_home)
    bin=$(write_fake_systemd_run)
    PATH="${bin}:/usr/bin:/bin" HOME="$home" "$script_under_test" agent todo-sample-agent-task
    args=$(cat "${DOTFILES_TEST_TMP}/systemd-run.args")
    [[ "$args" == --user\ --collect\ --unit=remind-run-agent-todo-sample-agent-task-* ]]
    [[ "$args" == *" ${home}/bin/foam-remind-agent-run todo-sample-agent-task" ]]
    [[ ! -e "${DOTFILES_TEST_TMP}/agent-helper.args" ]]
    ;;
remind-run-dotfiles-health-queues-helper)
    home=$(make_fake_home)
    bin=$(write_fake_systemd_run)
    PATH="${bin}:/usr/bin:/bin" HOME="$home" "$script_under_test" dotfiles-health update
    args=$(cat "${DOTFILES_TEST_TMP}/systemd-run.args")
    [[ "$args" == --user\ --collect\ --unit=remind-run-dotfiles-health-update-* ]]
    [[ "$args" == *" ${home}/bin/dotfiles-health update" ]]
    [[ ! -e "${DOTFILES_TEST_TMP}/dotfiles-health.args" ]]
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
