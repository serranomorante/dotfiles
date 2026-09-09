#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless terminal statusline mode-label
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-case: terminal-statusline-prefix-normal
# dotfiles-test-case: terminal-statusline-prefix-insert
# dotfiles-test-case: terminal-statusline-prefix-clears-off-terminal
# dotfiles-test-case: terminal-statusline-prefix-win-closed
# dotfiles-test-case: terminal-statusline-prefix-tick-stops-on-finished
# dotfiles-test-case: terminal-statusline-prefix-task-context
# dotfiles-test-case: terminal-statusline-prefix-agent-context
# dotfiles-test-case: terminal-statusline-prefix-overseer-error-contained
# dotfiles-test-case: terminal-statusline-prefix-task-without-id
# dotfiles-test-case: terminal-statusline-prefix-highlight-groups

# Purpose: Guard the NORMAL/TERMINAL mode prefix that terminal_statusline.lua
# prepends to the window-local statusline while the current window shows a
# terminal buffer, and verify the baseline statusline is preserved verbatim.
# Terminal mode itself is simulated by overriding vim.fn.mode(), because a
# headless nvim cannot reliably enter Terminal mode (the 't' state) without an
# attached UI.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    "$nvim_bin" --headless --noplugin -u NONE -i NONE -c "set rtp^=${rtp}" -S "$lua_file"
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

case "${DOTFILES_TEST_CASE:-}" in
terminal-statusline-prefix-normal)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-normal.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  assert(baseline ~= "", "expected a non-empty baseline statusline")' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  assert(vim.bo[termbuf].buftype == "terminal", "buffer should be a terminal")' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local expected = "%#CustomTerminalModeNormal# NORMAL %* " .. baseline' \
        '  assert(vim.wo[winid].statusline == expected, "prefixed statusline expected, got: " .. tostring(vim.wo[winid].statusline))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-insert)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-insert.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  assert(vim.bo[termbuf].buftype == "terminal", "buffer should be a terminal")' \
        '  vim.fn.mode = function() return "t" end' \
        '  vim.api.nvim_exec_autocmds("TermEnter", { modeline = false })' \
        '  local expected = "%#CustomTerminalModeInsert# TERMINAL %* " .. baseline' \
        '  assert(vim.wo[winid].statusline == expected, "terminal prefix expected, got: " .. tostring(vim.wo[winid].statusline))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-clears-off-terminal)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-clears.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  assert((vim.wo[winid].statusline or ""):find("CustomTerminalModeNormal", 1, true), "prefix expected while on terminal")' \
        '  local code = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_win_set_buf(winid, code)' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local eff = vim.o.statusline' \
        '  assert(eff == baseline, "statusline should fall back to baseline, got: " .. tostring(eff))' \
        '  assert(not (vim.wo[winid].statusline or ""):find("CustomTerminalMode", 1, true), "prefix must clear off a terminal")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-win-closed)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-win-closed.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  local base_win = vim.api.nvim_get_current_win()' \
        '  vim.cmd.vsplit()' \
        '  local termwin = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(termwin, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  assert((vim.wo[termwin].statusline or ""):find("CustomTerminalModeNormal", 1, true), "prefix expected on terminal window")' \
        '  vim.api.nvim_win_close(termwin, true)' \
        '  assert(vim.api.nvim_win_is_valid(base_win), "base window should survive the close")' \
        '  assert(vim.o.statusline == baseline, "baseline statusline should be restored, got: " .. tostring(vim.o.statusline))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-tick-stops-on-finished)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-tick.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  local task = { id = 11, status = "RUNNING", name = "ansible task", metadata = {}, get_bufnr = function() return termbuf end }' \
        '  vim.b[termbuf].overseer_task = 11' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function() return { get = function(id) return id == 11 and task or nil end } end' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("running", 1, true) and st:find("0:00", 1, true), "running prefix expected, got: " .. st)' \
        '  task.status = "CANCELED"' \
        '  vim.wait(1500, function() return false end, 50)' \
        '  st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("canceled", 1, true), "tick should surface the finished state, got: " .. st)' \
        '  assert(not st:find("0:00", 1, true) and not st:find("running", 1, true), "stale state in: " .. st)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-task-context)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-task.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  local task = { id = 7, status = "RUNNING", name = "demo task", metadata = {}, get_bufnr = function() return termbuf end }' \
        '  vim.b[termbuf].overseer_task = 7' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function() return { get = function(id) return id == 7 and task or nil end } end' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("CustomTerminalStatusActive", 1, true), "running state hl expected in: " .. st)' \
        '  assert(st:find("running", 1, true), "running state word expected in: " .. st)' \
        '  assert(st:find("0:00", 1, true), "running duration expected in: " .. st)' \
        '  assert(not st:find("demo task", 1, true), "titles belong to the plain statusline, got: " .. st)' \
        '  assert(st:sub(-#baseline) == baseline, "baseline must be preserved verbatim")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-agent-context)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-agent.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  local task = { id = 9, status = "RUNNING", name = "demo session", metadata = { agent_provider = "opencode", agent_session_id = "ses_abc123", agent_role = "master", agent_state = "awaiting_choice" }, get_bufnr = function() return termbuf end }' \
        '  vim.b[termbuf].overseer_task = 9' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function() return { get = function(id) return id == 9 and task or nil end } end' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("CustomTerminalStatusWarn", 1, true), "awaiting warn hl expected in: " .. st)' \
        '  assert(st:find("needs input", 1, true), "awaiting state word expected in: " .. st)' \
        '  assert(not st:find("demo session", 1, true), "titles belong to the plain statusline, got: " .. st)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-overseer-error-contained)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-overseer-error.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local baseline = vim.api.nvim_get_option_value("statusline", { scope = "global" })' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  vim.b[termbuf].overseer_task = 13' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function() return { get = function() error("stale task") end } end' \
        '  vim.fn.mode = function() return "n" end' \
        '  local ok, err = pcall(vim.api.nvim_exec_autocmds, "BufEnter", { modeline = false })' \
        '  assert(ok, "refresh error must not escape: " .. tostring(err))' \
        '  local st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("CustomTerminalModeNormal", 1, true), "mode chip should survive, got: " .. st)' \
        '  assert(not st:find("running", 1, true), "stale task must not render, got: " .. st)' \
        '  assert(st:sub(-#baseline) == baseline, "baseline must be preserved verbatim")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-task-without-id)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-task-without-id.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.terminal_statusline").setup()' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local termbuf = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_win_set_buf(winid, termbuf)' \
        '  vim.fn.termopen({ "sh", "-c", "printf ok" })' \
        '  local task = { id = nil, status = "RUNNING", name = "idless task", metadata = {}, get_bufnr = function() return termbuf end }' \
        '  vim.b[termbuf].overseer_task = 17' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function() return { get = function(id) return id == 17 and task or nil end } end' \
        '  vim.fn.mode = function() return "n" end' \
        '  vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })' \
        '  local st = vim.wo[winid].statusline or ""' \
        '  assert(st:find("running", 1, true), "running word expected in: " .. st)' \
        '  assert(not st:find("0:00", 1, true) and not st:find("·", 1, true), "no id must skip duration, got: " .. st)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
terminal-statusline-prefix-highlight-groups)
    lua_file="${DOTFILES_TEST_TMP}/terminal-statusline-prefix-highlight.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/colors/default.lua")' \
        '  local normal = vim.api.nvim_get_hl(0, { name = "CustomTerminalModeNormal" })' \
        '  assert(normal.bg, "CustomTerminalModeNormal should define a chip background")' \
        '  assert(normal.fg, "CustomTerminalModeNormal should define text color")' \
        '  local insert = vim.api.nvim_get_hl(0, { name = "CustomTerminalModeInsert" })' \
        '  assert(insert.fg, "CustomTerminalModeInsert should define text color")' \
        '  for _, name in ipairs({ "CustomTerminalDim", "CustomTerminalStatusActive", "CustomTerminalStatusOk", "CustomTerminalStatusWarn", "CustomTerminalStatusErr" }) do' \
        '    local hl = vim.api.nvim_get_hl(0, { name = name })' \
        '    assert(hl.fg, name .. " should define a foreground")' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
