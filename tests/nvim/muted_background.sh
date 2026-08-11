#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless muted-background winhl
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-case: muted-background-applies-to-markdown-and-clears
# dotfiles-test-case: muted-background-excludes-persistent-scratch
# dotfiles-test-case: muted-background-applies-to-agent-output-and-dispose
# dotfiles-test-case: muted-background-highlight-defines-fg-and-bg

# Purpose: Guard the muted gray background + dimmed foreground convention applied
# to agent task outputs and markdown buffers via a window-local Normal override.
# Add a new filetype to the convention by extending is_markdown_buffer /
# is_muted_background_buffer in serranomorante/utils.lua and a matching case here.

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
muted-background-applies-to-markdown-and-clears)
    lua_file="${DOTFILES_TEST_TMP}/muted-background-markdown.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local md = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_set_option_value("filetype", "markdown", { buf = md })' \
        '  vim.api.nvim_win_set_buf(winid, md)' \
        '  local winhl = vim.wo[winid].winhl' \
        '  assert(winhl:find("Normal:CustomMutedBg", 1, true), "markdown window should be muted, got: " .. winhl)' \
        '  local health = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_set_option_value("filetype", "markdown.system_health", { buf = health })' \
        '  vim.api.nvim_win_set_buf(winid, health)' \
        '  assert(vim.wo[winid].winhl:find("Normal:CustomMutedBg", 1, true), "markdown.system_health should be muted")' \
        '  local code = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_set_option_value("filetype", "lua", { buf = code })' \
        '  vim.api.nvim_win_set_buf(winid, code)' \
        '  winhl = vim.wo[winid].winhl' \
        '  assert(not winhl:find("CustomMutedBg", 1, true), "code window should be stripped, got: " .. winhl)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
muted-background-excludes-persistent-scratch)
    lua_file="${DOTFILES_TEST_TMP}/muted-background-scratch.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local scratch = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_set_option_value("filetype", "markdown.scratch", { buf = scratch })' \
        '  vim.b[scratch].persistent_scratch = true' \
        '  vim.api.nvim_win_set_buf(winid, scratch)' \
        '  local winhl = vim.wo[winid].winhl' \
        '  assert(not winhl:find("CustomMutedBg", 1, true), "persistent scratch should not be muted, got: " .. winhl)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
muted-background-applies-to-agent-output-and-dispose)
    lua_file="${DOTFILES_TEST_TMP}/muted-background-agent.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local bufnr = vim.api.nvim_create_buf(true, false)' \
        '  vim.api.nvim_win_set_buf(winid, bufnr)' \
        '  local task = {' \
        '    id = 4321,' \
        '    name = "codex: demo",' \
        '    metadata = { agent_session = true, agent_provider = "codex", agent_session_id = "abc123" },' \
        '    get_bufnr = function() return bufnr end,' \
        '  }' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return { get = function(id) return id == task.id and task or nil end }' \
        '  end' \
        '  vim.b[bufnr].overseer_task = task.id' \
        '  utils.attach_overseer_task_output_navigation(bufnr)' \
        '  local winhl = vim.wo[winid].winhl' \
        '  assert(winhl:find("Normal:CustomMutedBg", 1, true), "agent window should be muted, got: " .. winhl)' \
        '  utils.cleanup_overseer_task_output_buffer(bufnr)' \
        '  winhl = vim.wo[winid].winhl' \
        '  assert(not winhl:find("CustomMutedBg", 1, true), "agent dispose should strip muted bg, got: " .. winhl)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
muted-background-highlight-defines-fg-and-bg)
    lua_file="${DOTFILES_TEST_TMP}/muted-background-highlight.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/colors/default.lua")' \
        '  local hl = vim.api.nvim_get_hl(0, { name = "CustomMutedBg" })' \
        '  assert(hl.fg, "CustomMutedBg should define a dimmed foreground")' \
        '  assert(hl.bg, "CustomMutedBg should define a background")' \
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
