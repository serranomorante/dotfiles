#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless tui fzf terminal
# dotfiles-test-firejail: disabled
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: fzf-pickers-enter-insert-mode-in-sequence
# dotfiles-test-case: fzf-overseer-task-action-picker-enters-insert-mode
# dotfiles-test-case: fzf-overseer-task-action-picker-tui-receives-terminal-input
# dotfiles-test-case: fzf-picker-insert-does-not-affect-plain-terminals

# Purpose: Verify picker terminals enter insert mode without changing the default for ordinary terminals.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-fzf.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-fzf.XXXXXX")
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

run_nvim_tui_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local nvim_cmd

    command -v script >/dev/null 2>&1 || {
        printf 'script(1) is not available; skipping TUI picker regression\n' >&2
        return 77
    }
    command -v timeout >/dev/null 2>&1 || {
        printf 'timeout(1) is not available; skipping TUI picker regression\n' >&2
        return 77
    }

    tui_runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-fzf-tui.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-fzf-tui.XXXXXX")
    tui_input_fifo="${DOTFILES_TEST_TMP}/tui-input"
    tui_typescript="${DOTFILES_TEST_TMP}/tui-typescript.log"
    tui_stdout_log="${DOTFILES_TEST_TMP}/tui-stdout.log"
    tui_stderr_log="${DOTFILES_TEST_TMP}/tui-stderr.log"
    mkdir -p "$tui_runtime_dir"
    mkfifo "$tui_input_fifo"
    exec 9<>"$tui_input_fifo"

    nvim_cmd="${nvim_bin} -n -u NONE -c 'set rtp^=${rtp}' -S '${lua_file}'"
    (
        export XDG_RUNTIME_DIR="$tui_runtime_dir"
        export TERM=xterm-256color
        timeout --foreground 12s script -qefc "$nvim_cmd" "$tui_typescript" <"$tui_input_fifo"
    ) >"$tui_stdout_log" 2>"$tui_stderr_log" &
    tui_pid=$!
}

finish_nvim_tui() {
    local rc

    exec 9>&-
    set +e
    wait "$tui_pid"
    rc=$?
    set -e
    rm -rf "$tui_runtime_dir"
    return "$rc"
}

abort_nvim_tui() {
    exec 9>&- || true
    if [ -n "${tui_pid:-}" ]; then
        kill "$tui_pid" >/dev/null 2>&1 || true
        wait "$tui_pid" >/dev/null 2>&1 || true
    fi
    if [ -n "${tui_runtime_dir:-}" ]; then rm -rf "$tui_runtime_dir"; fi
}

wait_for_tui_file() {
    local path=$1
    local attempts=${2:-500}
    local attempt

    for ((attempt = 0; attempt < attempts; attempt++)); do
        [ -e "$path" ] && return 0
        sleep 0.02
    done
    return 1
}

print_tui_debug() {
    local file

    for file in "$tui_stderr_log" "$tui_stdout_log" "$tui_typescript"; do
        [ -s "$file" ] || continue
        printf '%s\n' "--- ${file##*/} ---" >&2
        sed -n '1,120p' "$file" | cat -v >&2
    done
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

install_fake_fzf() {
    local fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/fzf" <<'SH'
#!/bin/sh
set -eu

count_file="${DOTFILES_TEST_TMP}/fzf-count"
if [ -f "$count_file" ]; then
    count=$(cat "$count_file")
else
    count=0
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
input_file="${DOTFILES_TEST_TMP}/fzf-input-${count}"
cat >"$input_file"
touch "${DOTFILES_TEST_TMP}/fzf-started-${count}"

release="${DOTFILES_TEST_TMP}/fzf-release-${count}"
while [ ! -e "$release" ]; do
    sleep 0.02
done

sed -n '1p' "$input_file"
SH
    chmod +x "${fake_bin}/fzf"
}

install_fake_tui_fzf() {
    local fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/fzf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

count_file="${DOTFILES_TEST_TMP}/fzf-count"
if [ -f "$count_file" ]; then
    count=$(cat "$count_file")
else
    count=0
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"

input_file="${DOTFILES_TEST_TMP}/fzf-input-${count}"
cat >"$input_file"
touch "${DOTFILES_TEST_TMP}/fzf-started-${count}"

if [ "$count" -eq 1 ]; then
    sed -n '1p' "$input_file"
    exit 0
fi

key_file="${DOTFILES_TEST_TMP}/fzf-key-${count}"
if IFS= read -rsn1 -t 10 key </dev/tty; then
    printf '%s' "$key" >"$key_file"
    sed -n '1p' "$input_file"
else
    printf 'timeout' >"$key_file"
    exit 124
fi
SH
    chmod +x "${fake_bin}/fzf"
}

case "${DOTFILES_TEST_CASE:-}" in
fzf-pickers-enter-insert-mode-in-sequence)
    install_fake_fzf
    lua_file="${DOTFILES_TEST_TMP}/fzf-pickers-enter-insert-mode-in-sequence.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local utils = require("serranomorante.utils")' \
        '  local tmp = vim.env.DOTFILES_TEST_TMP' \
        '  local done = false' \
        '  local source_winid = vim.api.nvim_get_current_win()' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  local utils_path = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/utils.lua"' \
        '  local utils_text = table.concat(vim.fn.readfile(utils_path), "\n")' \
        '  assert(utils_text:find("vim%.schedule%(%s*function%(%)[%s\n]*restore_source_window%(%)[%s\n]*if opts%.sink") ~= nil, "fzf sinks should run after picker cleanup in the source window so nested pickers can start insert mode")' \
        '  local picker_insert_buffers = {}' \
        '  local original_input = vim.api.nvim_input' \
        '  vim.api.nvim_input = function(keys)' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    if keys == "i" then picker_insert_buffers[bufnr] = (picker_insert_buffers[bufnr] or 0) + 1 end' \
        '    return original_input(keys)' \
        '  end' \
        '  local function exists(path)' \
        '    return vim.uv.fs_stat(path) ~= nil' \
        '  end' \
        '  local function current_buffer_is_picker_terminal()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return vim.bo[bufnr].buftype == "terminal" and vim.bo[bufnr].filetype == "fzf"' \
        '  end' \
        '  local function current_picker_requested_insert()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return current_buffer_is_picker_terminal() and (picker_insert_buffers[bufnr] or 0) > 0' \
        '  end' \
        '  utils.fzf({' \
        '    source = { "first" },' \
        '    prompt = "First picker",' \
        '    sink = function(entry)' \
        '      assert(vim.api.nvim_get_current_win() == source_winid, "first picker sink should return to the source window")' \
        '      assert(vim.api.nvim_get_current_buf() == source_bufnr, "first picker sink should return to the source buffer")' \
        '      assert(entry == "first", entry)' \
        '      utils.fzf({' \
        '        source = { "second" },' \
        '        prompt = "Second picker",' \
        '        sink = function(second_entry)' \
        '          assert(vim.api.nvim_get_current_win() == source_winid, "nested picker sink should return to the source window")' \
        '          assert(vim.api.nvim_get_current_buf() == source_bufnr, "nested picker sink should return to the source buffer")' \
        '          assert(second_entry == "second", second_entry)' \
        '          done = true' \
        '        end,' \
        '      })' \
        '    end,' \
        '  })' \
        '  assert(vim.wait(2000, function() return exists(tmp .. "/fzf-started-1") and current_picker_requested_insert() end, 10), "first picker did not request picker-scoped terminal insert")' \
        '  vim.fn.writefile({ "release" }, tmp .. "/fzf-release-1")' \
        '  assert(vim.wait(2000, function() return exists(tmp .. "/fzf-started-2") and current_picker_requested_insert() end, 10), "second picker did not request picker-scoped terminal insert")' \
        '  local second_bufnr = vim.api.nvim_get_current_buf()' \
        '  local insert_before_focus_recovery = picker_insert_buffers[second_bufnr] or 0' \
        '  vim.api.nvim_exec_autocmds("WinEnter", { buffer = second_bufnr })' \
        '  assert(vim.wait(1000, function() return (picker_insert_buffers[second_bufnr] or 0) > insert_before_focus_recovery end, 10), "picker should request insert mode after picker-local focus")' \
        '  vim.fn.writefile({ "release" }, tmp .. "/fzf-release-2")' \
        '  assert(vim.wait(2000, function() return done end, 10), "second picker sink did not run")' \
        '  assert(vim.fn.readfile(tmp .. "/fzf-count")[1] == "2", "expected exactly two fake fzf invocations")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
fzf-overseer-task-action-picker-enters-insert-mode)
    install_fake_fzf
    lua_file="${DOTFILES_TEST_TMP}/fzf-overseer-task-action-picker-enters-insert-mode.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local utils = require("serranomorante.utils")' \
        '  vim.ui.select = utils.select' \
        '  local tmp = vim.env.DOTFILES_TEST_TMP' \
        '  local task = { id = 12, name = "demo task", time_start = 1 }' \
        '  local selected_action' \
        '  package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_sessions"] = function()' \
        '    return { task_session_mtime = function() return nil end, capture_task_action_prompt_context = function() return nil end, prompt_from_task_action_context = function() return nil end, prompt_from_context = function() return nil end }' \
        '  end' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return {' \
        '      list_tasks = function() return { task } end,' \
        '      get = function(id) return id == task.id and task or nil end,' \
        '      sort_finished_recently = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.action_util"] = nil' \
        '  package.preload["overseer.action_util"] = function()' \
        '    return {' \
        '      run_task_action = function(selected_task)' \
        '        assert(selected_task == task, "wrong task selected")' \
        '        vim.ui.select({ { name = "dispose", desc = "Dispose task" } }, {' \
        '          prompt = "Actions: " .. selected_task.name,' \
        '          kind = "overseer_task_options",' \
        '          format_item = function(action) return action.name end,' \
        '        }, function(action) selected_action = action end)' \
        '      end,' \
        '    }' \
        '  end' \
        '  local picker_insert_buffers = {}' \
        '  local prompt_by_buffer = {}' \
        '  local original_input = vim.api.nvim_input' \
        '  local function title_text(title)' \
        '    if type(title) == "string" then return title end' \
        '    if type(title) ~= "table" then return nil end' \
        '    local parts = {}' \
        '    for _, chunk in ipairs(title) do' \
        '      table.insert(parts, type(chunk) == "table" and chunk[1] or tostring(chunk))' \
        '    end' \
        '    return table.concat(parts)' \
        '  end' \
        '  vim.api.nvim_input = function(keys)' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    if keys == "i" then picker_insert_buffers[bufnr] = (picker_insert_buffers[bufnr] or 0) + 1 end' \
        '    prompt_by_buffer[bufnr] = title_text(vim.api.nvim_win_get_config(0).title)' \
        '    return original_input(keys)' \
        '  end' \
        '  local function exists(path)' \
        '    return vim.uv.fs_stat(path) ~= nil' \
        '  end' \
        '  local function current_picker_prompt()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    if vim.bo[bufnr].buftype ~= "terminal" or vim.bo[bufnr].filetype ~= "fzf" then return nil end' \
        '    return prompt_by_buffer[bufnr] or title_text(vim.api.nvim_win_get_config(0).title)' \
        '  end' \
        '  require("serranomorante.plugins.jobs.overseer_task_actions").run_recent_task_action()' \
        '  assert(vim.wait(2000, function() return exists(tmp .. "/fzf-started-1") and current_picker_prompt() == "Select task" end, 10), "task picker did not enter insert mode")' \
        '  vim.fn.writefile({ "release" }, tmp .. "/fzf-release-1")' \
        '  assert(vim.wait(2000, function() return exists(tmp .. "/fzf-started-2") and current_picker_prompt() == "Actions: demo task" end, 10), "task action picker did not enter insert mode")' \
        '  local action_bufnr = vim.api.nvim_get_current_buf()' \
        '  local before = picker_insert_buffers[action_bufnr] or 0' \
        '  vim.api.nvim_exec_autocmds("WinEnter", { buffer = action_bufnr })' \
        '  assert(vim.wait(1000, function() return (picker_insert_buffers[action_bufnr] or 0) > before end, 10), "task action picker should request insert mode through its picker-local focus autocmd")' \
        '  vim.fn.writefile({ "release" }, tmp .. "/fzf-release-2")' \
        '  assert(vim.wait(2000, function() return selected_action ~= nil end, 10), "task action picker sink did not run")' \
        '  assert(selected_action.name == "dispose", selected_action.name)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
fzf-overseer-task-action-picker-tui-receives-terminal-input)
    install_fake_tui_fzf
    lua_file="${DOTFILES_TEST_TMP}/fzf-overseer-task-action-picker-tui-receives-terminal-input.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local utils = require("serranomorante.utils")' \
        '  vim.ui.select = utils.select' \
        '  local tmp = vim.env.DOTFILES_TEST_TMP' \
        '  local task = { id = 12, name = "demo task", time_start = 1 }' \
        '  package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_sessions"] = function()' \
        '    return { task_session_mtime = function() return nil end, capture_task_action_prompt_context = function() return nil end, prompt_from_task_action_context = function() return nil end, prompt_from_context = function() return nil end }' \
        '  end' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return {' \
        '      list_tasks = function() return { task } end,' \
        '      get = function(id) return id == task.id and task or nil end,' \
        '      sort_finished_recently = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.action_util"] = nil' \
        '  package.preload["overseer.action_util"] = function()' \
        '    return {' \
        '      run_task_action = function(selected_task)' \
        '        assert(selected_task == task, "wrong task selected")' \
        '        vim.ui.select({ { name = "dispose", desc = "Dispose task" } }, {' \
        '          prompt = "Actions: " .. selected_task.name,' \
        '          kind = "overseer_task_options",' \
        '          format_item = function(action) return action.name end,' \
        '        }, function(action)' \
        '          assert(action and action.name == "dispose", vim.inspect(action))' \
        '          vim.fn.writefile({ action.name }, tmp .. "/selected-action")' \
        '          vim.cmd.qa({ bang = true })' \
        '        end)' \
        '      end,' \
        '    }' \
        '  end' \
        '  local function title_text(title)' \
        '    if type(title) == "string" then return title end' \
        '    if type(title) ~= "table" then return nil end' \
        '    local parts = {}' \
        '    for _, chunk in ipairs(title) do table.insert(parts, type(chunk) == "table" and chunk[1] or tostring(chunk)) end' \
        '    return table.concat(parts)' \
        '  end' \
        '  local function note_action_picker_terminal_mode()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    if vim.bo[bufnr].buftype ~= "terminal" or vim.bo[bufnr].filetype ~= "fzf" then return end' \
        '    if vim.api.nvim_get_mode().mode ~= "t" then return end' \
        '    if title_text(vim.api.nvim_win_get_config(0).title) == "Actions: demo task" then' \
        '      vim.fn.writefile({ "terminal" }, tmp .. "/action-picker-terminal-mode")' \
        '    end' \
        '  end' \
        '  vim.api.nvim_create_autocmd({ "ModeChanged", "BufEnter", "WinEnter", "TermOpen" }, { callback = note_action_picker_terminal_mode })' \
        '  require("serranomorante.plugins.jobs.overseer_task_actions").run_recent_task_action()' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_tui_lua_file "$lua_file"
    if ! wait_for_tui_file "${DOTFILES_TEST_TMP}/action-picker-terminal-mode"; then
        printf 'action picker never reached real terminal mode\n' >&2
        print_tui_debug
        abort_nvim_tui
        exit 1
    fi
    printf 'x' >&9
    if ! finish_nvim_tui; then
        print_tui_debug
        exit 1
    fi
    if [ "$(cat "${DOTFILES_TEST_TMP}/fzf-key-2")" != "x" ]; then
        printf 'second fzf did not receive terminal input; got: %s\n' "$(cat "${DOTFILES_TEST_TMP}/fzf-key-2")" >&2
        exit 1
    fi
    if [ "$(cat "${DOTFILES_TEST_TMP}/selected-action")" != "dispose" ]; then
        printf 'unexpected selected action: %s\n' "$(cat "${DOTFILES_TEST_TMP}/selected-action")" >&2
        exit 1
    fi
    ;;
fzf-picker-insert-does-not-affect-plain-terminals)
    lua_file="${DOTFILES_TEST_TMP}/fzf-picker-insert-does-not-affect-plain-terminals.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.utils")' \
        '  local input_calls = 0' \
        '  local original_input = vim.api.nvim_input' \
        '  vim.api.nvim_input = function(keys)' \
        '    if keys == "i" then input_calls = input_calls + 1 end' \
        '    return original_input(keys)' \
        '  end' \
        '  vim.cmd.enew()' \
        '  local bufnr = vim.api.nvim_get_current_buf()' \
        '  local job = vim.fn.termopen({ "sh", "-c", "sleep 1" })' \
        '  assert(job > 0, "termopen failed")' \
        '  assert(vim.bo[bufnr].buftype == "terminal", "expected a terminal buffer")' \
        '  vim.wait(100, function() return false end, 10)' \
        '  assert(input_calls == 0, "plain terminal should not receive picker terminal insert input")' \
        '  vim.fn.jobstop(job)' \
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
