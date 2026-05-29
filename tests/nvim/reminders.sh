#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim remind agent firejail
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: reminders-agent-run-uses-attached-id
# dotfiles-test-case: reminders-agent-run-without-id-does-not-emit-run

# Purpose: Verify generated Remind RUN entries for @run agent TODOs.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_remind_update() {
    "$nvim_bin" --headless -u NONE \
        -c "set rtp^=${rtp}" \
        -c "source ${rtp}/after/plugin/reminders.lua" \
        -c "RemindUpdate" \
        -c "qa!"
}

make_foam_note() {
    local lines=("$@")

    mkdir -p "${HOME}/data/notes/foam/misc/tasks" "${HOME}/.config/remind"
    printf '%s\n' "${lines[@]}" >"${HOME}/data/notes/foam/misc/tasks/todos.sample.md"
}

case "${DOTFILES_TEST_CASE:-}" in
reminders-agent-run-uses-attached-id)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample task**" \
        "  @id todo-sample-agent-task" \
        "" \
        "  \`\`\`remind" \
        "  @run agent" \
        "  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3" \
        "  \`\`\`"

    run_remind_update

    rg -q "MSG \\*\\*Review sample task\\*\\*" "${HOME}/.config/remind/reminders.rem"
    rg -q "RUN '${HOME}/bin/remind-run' 'agent' 'todo-sample-agent-task'" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-agent-run-without-id-does-not-emit-run)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample task**" \
        "" \
        "  \`\`\`remind" \
        "  @run agent" \
        "  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3" \
        "  \`\`\`"

    run_remind_update >"${DOTFILES_TEST_TMP}/nvim.out" 2>&1

    rg -q "MSG \\*\\*Review sample task\\*\\*" "${HOME}/.config/remind/reminders.rem"
    ! rg -q "RUN .*remind-run.*agent" "${HOME}/.config/remind/reminders.rem"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
