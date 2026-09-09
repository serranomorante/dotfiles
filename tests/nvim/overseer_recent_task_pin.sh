#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless overseer task-list open-recent
# dotfiles-test-firejail: disabled
# dotfiles-test-case: overseer-open-recent-pins-current-from-own-output
# dotfiles-test-case: overseer-open-recent-pins-current-source-task
# dotfiles-test-case: overseer-open-recent-keeps-order-from-plain-buffer
# dotfiles-test-case: overseer-open-recent-single-current-skips-picker
# dotfiles-test-case: overseer-task-actions-picker-keeps-order-from-task-buffer

# Purpose: Guard <leader>od pinning: invoked from an Overseer task output, the
# recent-task listing puts that task first, while plain buffers and the task
# action picker keep their recent-activity order.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-task-pin.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-task-pin.XXXXXX")
    mkdir -p "$runtime_dir"
    (
        export XDG_RUNTIME_DIR="$runtime_dir"
        "$nvim_bin" \
            --headless \
            -u NONE \
            -c "set rtp^=${rtp}" \
            -S "$lua_file"
    ) || rc=$?
    rm -rf "$runtime_dir"
    return "$rc"
}

run_pin_test() {
    local lua_file="${DOTFILES_TEST_TMP}/overseer-recent-task-pin.lua"
    cat >"$lua_file" <<'LUA'
local function main()
    local ota = require("serranomorante.plugins.jobs.overseer_task_actions")
    local case = vim.env.DOTFILES_TEST_CASE
    local bufnr = vim.api.nvim_get_current_buf()

    local task_other = { id = 1, name = "newer other task", time_start = 20 }
    local task_current = { id = 2, name = "current task output", time_start = 10 }
    local listed = { task_other, task_current }

    local function by_id(id)
        if id == task_other.id then return task_other end
        if id == task_current.id then return task_current end
        return nil
    end

    package.loaded["overseer.task_list"] = nil
    package.preload["overseer.task_list"] = function()
        return {
            list_tasks = function() return listed end,
            get = by_id,
            sort_finished_recently = function() return false end,
        }
    end
    package.loaded["overseer.action_util"] = nil
    package.preload["overseer.action_util"] = function()
        return { run_task_action = function() error("no plain action expected in pin test") end }
    end
    package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil
    package.preload["serranomorante.plugins.jobs.agent_sessions"] = function()
        return {
            task_session_mtime = function() return nil end,
            capture_task_action_prompt_context = function()
                local source_id = vim.b[bufnr].overseer_task
                return { visual_prompt = nil, source_task = by_id(source_id) }
            end,
            prompt_from_task_action_context = function() return nil end,
            prompt_from_context = function() return nil end,
        }
    end

    local select_calls = 0
    local shown_ids = {}
    vim.ui.select = function(items)
        select_calls = select_calls + 1
        shown_ids = {}
        for _, item in ipairs(items) do shown_ids[#shown_ids + 1] = item.id end
    end

    if case == "overseer-open-recent-pins-current-from-own-output" then
        vim.b[bufnr].overseer_task = task_current.id
        ota.open_recent_task({ noop_task_id = task_current.id })
        assert(select_calls == 1, ("picker expected once, called %d"):format(select_calls))
        assert(shown_ids[1] == task_current.id, ("current task should be pinned first, got %s"):format(vim.inspect(shown_ids)))
        assert(shown_ids[2] == task_other.id, ("other task should follow pinned task, got %s"):format(vim.inspect(shown_ids)))
    elseif case == "overseer-open-recent-pins-current-source-task" then
        vim.b[bufnr].overseer_task = task_current.id
        ota.open_recent_task()
        assert(select_calls == 1, ("picker expected once, called %d"):format(select_calls))
        assert(shown_ids[1] == task_current.id, ("current buffer task should be pinned from source, got %s"):format(vim.inspect(shown_ids)))
        assert(shown_ids[2] == task_other.id, vim.inspect(shown_ids))
    elseif case == "overseer-open-recent-keeps-order-from-plain-buffer" then
        ota.open_recent_task()
        assert(select_calls == 1, ("picker expected once, called %d"):format(select_calls))
        assert(shown_ids[1] == task_other.id, ("plain buffer should keep recent order, got %s"):format(vim.inspect(shown_ids)))
        assert(shown_ids[2] == task_current.id, vim.inspect(shown_ids))
    elseif case == "overseer-open-recent-single-current-skips-picker" then
        vim.b[bufnr].overseer_task = task_current.id
        listed = { task_current }
        ota.open_recent_task({ noop_task_id = task_current.id })
        assert(select_calls == 0, ("picker should be skipped for the only current task, called %d"):format(select_calls))
    elseif case == "overseer-task-actions-picker-keeps-order-from-task-buffer" then
        vim.b[bufnr].overseer_task = task_current.id
        ota.run_recent_task_action()
        assert(select_calls == 1, ("picker expected once, called %d"):format(select_calls))
        assert(shown_ids[1] == task_other.id, ("task action picker should not pin, got %s"):format(vim.inspect(shown_ids)))
        assert(shown_ids[2] == task_current.id, vim.inspect(shown_ids))
    else
        error("unknown DOTFILES_TEST_CASE: " .. tostring(case))
    end
    vim.cmd.qa({ bang = true })
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
    print(err)
    vim.cmd.cquit({ bang = true })
end
LUA
    run_nvim_lua_file "$lua_file"
}

case "${DOTFILES_TEST_CASE:-}" in
overseer-open-recent-pins-current-from-own-output)
    run_pin_test
    ;;
overseer-open-recent-pins-current-source-task)
    run_pin_test
    ;;
overseer-open-recent-keeps-order-from-plain-buffer)
    run_pin_test
    ;;
overseer-open-recent-single-current-skips-picker)
    run_pin_test
    ;;
overseer-task-actions-picker-keeps-order-from-task-buffer)
    run_pin_test
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
