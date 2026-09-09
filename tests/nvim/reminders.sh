#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim remind agent firejail
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-case: reminders-agent-run-uses-attached-id
# dotfiles-test-case: reminders-agent-run-emits-agenda-metadata
# dotfiles-test-case: reminders-agent-run-without-id-does-not-emit-run
# dotfiles-test-case: reminders-update-reports-remind-warnings
# dotfiles-test-case: reminders-ignore-remind-usage-doc
# dotfiles-test-case: reminders-ignore-agent-run-output
# dotfiles-test-case: reminders-restart-remind-on-change
# dotfiles-test-case: reminders-no-restart-when-unchanged
# dotfiles-test-case: reminders-long-body-fence-found
# dotfiles-test-case: reminders-long-body-intermediate-code-fence
# dotfiles-test-case: reminders-execution-metadata-outside-fence
# dotfiles-test-case: reminders-startup-foam-cwd-runs-remind
# dotfiles-test-case: reminders-startup-other-cwd-skips-remind
# dotfiles-test-case: reminders-startup-headless-skips-remind

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

make_fake_systemctl() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/systemctl" <<'BASH'
#!/bin/sh
printf 'systemctl %s\n' "$*" >>"${DOTFILES_TEST_TMP}/systemctl.log"
BASH
    chmod +x "${bin}/systemctl"
    printf '%s\n' "$bin"
}

write_startup_probe() {
    local probe=$1
    cat >"$probe" <<'LUA'
local marker = vim.env.DOTFILES_TEST_TMP .. "/remind-startup.marker"
local loaded = vim.env.DOTFILES_TEST_TMP .. "/remind-startup.loaded"
os.remove(marker)
os.remove(loaded)
local plugin = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/after/plugin/reminders.lua"
vim.cmd.source(plugin)
vim.fn.writefile({ "loaded" }, loaded)
vim.api.nvim_create_user_command("Remind", function()
  vim.fn.writefile({ "remind-called" }, marker)
end, { force = true, nargs = "*", bar = true })
if vim.env.DOTFILES_TEST_STUB_UI == "1" then
  vim.api.nvim_list_uis = function() return { { width = 80, height = 24 } } end
end
vim.api.nvim_exec_autocmds("VimEnter", { group = "remind_startup" })
vim.wait(1500, function() return vim.fn.filereadable(marker) == 1 end, 10)
vim.cmd.qa({ bang = true })
LUA
}

run_startup_probe() {
    local cwd=$1
    local stub_ui=$2
    local probe=$3
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-reminders.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-reminders.XXXXXX")
    mkdir -p "$runtime_dir"
    (
        cd "$cwd"
        export XDG_RUNTIME_DIR="$runtime_dir"
        export DOTFILES_TEST_STUB_UI="$stub_ui"
        "$nvim_bin" --headless -u NONE \
            -c "set rtp^=${rtp}" \
            -S "$probe"
    ) || rc=$?
    rm -rf "$runtime_dir"
    return "$rc"
}

startup_probe_marker="${DOTFILES_TEST_TMP}/remind-startup.marker"
startup_probe_loaded="${DOTFILES_TEST_TMP}/remind-startup.loaded"

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
reminders-agent-run-emits-agenda-metadata)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample task**" \
        "  @id todo-sample-agent-task" \
        "  @tags #autotrigger #sample" \
        "" \
        "  \`\`\`remind" \
        "  @run agent" \
        "  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3" \
        "  \`\`\`"

    run_remind_update

    rg -q "^# remind-agenda-meta run=agent tags=#autotrigger,#sample$" "${HOME}/.config/remind/reminders.rem"
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
    refute rg -q "RUN .*remind-run.*agent" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-update-reports-remind-warnings)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample warning**" \
        "" \
        "  \`\`\`remind" \
        "  REM FooBarBaz 2026" \
        "  \`\`\`"

    run_remind_update >"${DOTFILES_TEST_TMP}/nvim.out" 2>&1

    rg -q "Missing REM type; assuming MSG" "${DOTFILES_TEST_TMP}/nvim.out"
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

    refute rg -q "Example documentation task" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-ignore-agent-run-output)
    make_foam_note_at "misc/agent-runs/2026-05/sample.md" \
        "# Agent run sample" \
        "" \
        "- [ ] **Example agent output task" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    run_remind_update

    refute rg -q "Example agent output task" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-restart-remind-on-change)
    bin=$(make_fake_systemctl)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample task**" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    PATH="${bin}:${PATH}" run_remind_update

    rg -q '^systemctl --user restart remind$' "${DOTFILES_TEST_TMP}/systemctl.log"
    ;;
reminders-no-restart-when-unchanged)
    bin=$(make_fake_systemctl)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review sample task**" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    PATH="${bin}:${PATH}" run_remind_update
    : >"${DOTFILES_TEST_TMP}/systemctl.log"
    PATH="${bin}:${PATH}" run_remind_update

    refute rg -q 'restart remind' "${DOTFILES_TEST_TMP}/systemctl.log"
    ;;
reminders-long-body-fence-found)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review long body task**" \
        "  @id todo-long-body-task" \
        "" \
        "  Body line 01" \
        "  Body line 02" \
        "  Body line 03" \
        "  Body line 04" \
        "  Body line 05" \
        "  Body line 06" \
        "  Body line 07" \
        "  Body line 08" \
        "  Body line 09" \
        "  Body line 10" \
        "  Body line 11" \
        "  Body line 12" \
        "  Body line 13" \
        "" \
        "  \`\`\`remind" \
        "  @run agent" \
        "  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3" \
        "  \`\`\`"

    run_remind_update

    rg -q "MSG \\*\\*Review long body task\\*\\*" "${HOME}/.config/remind/reminders.rem"
    rg -q "RUN '${HOME}/bin/remind-run' 'agent' 'todo-long-body-task'" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-long-body-intermediate-code-fence)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review task with code block in body**" \
        "" \
        "  Body line 01" \
        "  Body line 02" \
        "  Body line 03" \
        "" \
        "  \`\`\`" \
        "  https://example.com/a" \
        "  https://example.com/b" \
        "  https://example.com/c" \
        "  \`\`\`" \
        "" \
        "  Body line 04" \
        "  Body line 05" \
        "" \
        "  \`\`\`remind" \
        "  REM jun 1 2026 AT 10:00" \
        "  \`\`\`"

    run_remind_update

    rg -q "MSG \\*\\*Review task with code block in body\\*\\*" "${HOME}/.config/remind/reminders.rem"
    refute rg -q "RUN .*remind-run" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-execution-metadata-outside-fence)
    make_foam_note \
        "# Sample | TODOS" \
        "" \
        "- [ ] **Review metadata task**" \
        "  @id todo-metadata-task" \
        "  @timeout 900" \
        "  @model gpt-5" \
        "" \
        "  \`\`\`remind" \
        "  @run agent" \
        "  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3" \
        "  \`\`\`"

    run_remind_update

    rg -q "MSG \\*\\*Review metadata task\\*\\*" "${HOME}/.config/remind/reminders.rem"
    rg -q "RUN '${HOME}/bin/remind-run' 'agent' 'todo-metadata-task'" "${HOME}/.config/remind/reminders.rem"
    refute rg -q "@timeout" "${HOME}/.config/remind/reminders.rem"
    refute rg -q "@model" "${HOME}/.config/remind/reminders.rem"
    ;;
reminders-startup-foam-cwd-runs-remind)
    foam="${HOME}/data/notes/foam"
    mkdir -p "$foam"
    probe="${DOTFILES_TEST_TMP}/remind-startup.lua"
    write_startup_probe "$probe"

    run_startup_probe "$foam" 1 "$probe"

    test -f "${startup_probe_loaded}"
    rg -q "remind-called" "$startup_probe_marker"
    ;;
reminders-startup-other-cwd-skips-remind)
    project="${DOTFILES_TEST_TMP}/project-a"
    mkdir -p "$project"
    probe="${DOTFILES_TEST_TMP}/remind-startup.lua"
    write_startup_probe "$probe"

    run_startup_probe "$project" 1 "$probe"

    test -f "${startup_probe_loaded}"
    refute test -f "${startup_probe_marker}"
    ;;
reminders-startup-headless-skips-remind)
    foam="${HOME}/data/notes/foam"
    mkdir -p "$foam"
    probe="${DOTFILES_TEST_TMP}/remind-startup.lua"
    write_startup_probe "$probe"

    run_startup_probe "$foam" 0 "$probe"

    test -f "${startup_probe_loaded}"
    refute test -f "${startup_probe_marker}"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
