#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim remind agent firejail
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: reminders-agent-run-uses-attached-id
# dotfiles-test-case: reminders-agent-run-without-id-does-not-emit-run
# dotfiles-test-case: reminders-ignore-remind-usage-doc
# dotfiles-test-case: reminders-ignore-agent-run-output

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
    make_foam_note_at "misc/tasks/todos.sample.md" "$@"
}

make_foam_note_at() {
    local path=$1
    shift
    local lines=("$@")

    mkdir -p "$(dirname "${HOME}/data/notes/foam/${path}")" "${HOME}/.config/remind"
    printf '%s\n' "${lines[@]}" >"${HOME}/data/notes/foam/${path}"
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
reminders-ignore-remind-usage-doc)
    make_foam_note_at "docs/agents/remind-usage.md" \
        "# Remind usage | Misc | Docs" \
        "" \
        "- [ ] **Example documentation task**" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    run_remind_update

    ! rg -q "Example documentation task" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-ignore-agent-run-output)
    make_foam_note_at "misc/agent-runs/2026-05/sample.md" \
        "# Agent run sample" \
        "" \
        "- [ ] **Example agent output task**" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    run_remind_update

    ! rg -q "Example agent output task" "${HOME}/.config/remind/reminders.rem"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
