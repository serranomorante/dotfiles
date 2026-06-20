#!/usr/bin/env bash

# Purpose: Sourced via BASH_ENV before every dotfiles test file so a failing
# command reports its exact file:line, exit code, and command text instead of
# dying silently under `set -e`. The test runner wires this up; nothing in a
# test file needs to opt in.
#
# Negative assertions: use `refute <command>` to assert a command must fail.
# Plain `! <command>` is exempt from `set -e`, so it neither aborts the case
# nor reaches the ERR trap, meaning the assertion silently passes even when the
# command succeeds. `refute` runs the command, fails the case when it succeeds,
# and reports the call site like any other failing command.

# errtrace: make the ERR trap fire inside functions and command substitutions
# too. The test file's own `set -euo pipefail` runs after this and leaves the
# trap and this option intact.
set -E

__dotfiles_test_report_err() {
    local rc=$1 cmd=$2
    # The trap can fire again as `set -e` unwinds nested functions; report once.
    [[ -n "${__dotfiles_test_err_reported:-}" ]] && return
    __dotfiles_test_err_reported=1

    {
        printf '>>> FAILED command (exit %s): %s\n' "$rc" "$cmd"
        # Walk the call stack; frame 1 is where the failing command lives.
        local i
        for ((i = 1; i < ${#BASH_SOURCE[@]}; i++)); do
            local fn=${FUNCNAME[i]:-}
            if [[ -n "$fn" && "$fn" != main && "$fn" != source ]]; then
                printf '>>>   at %s:%s in %s()\n' \
                    "${BASH_SOURCE[i]}" "${BASH_LINENO[i - 1]}" "$fn"
            else
                printf '>>>   at %s:%s\n' \
                    "${BASH_SOURCE[i]}" "${BASH_LINENO[i - 1]}"
            fi
        done
    } >&2
}

trap '__dotfiles_test_report_err "$?" "$BASH_COMMAND"' ERR

# refute CMD [ARGS...]: assert that CMD fails. Returns 0 when CMD exits
# non-zero (the assertion holds) and 1 when CMD succeeds (the assertion fails),
# so the caller's `set -e` aborts the case. Reports the call site directly and
# suppresses the generic ERR-trap line to keep the output to one message.
refute() {
    if "$@"; then
        __dotfiles_test_err_reported=1
        {
            printf '>>> REFUTE failed: command succeeded but was expected to fail\n'
            printf '>>> command: %s\n' "$*"
            printf '>>>   at %s:%s\n' "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}"
        } >&2
        return 1
    fi
    return 0
}
