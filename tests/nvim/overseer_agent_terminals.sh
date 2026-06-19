#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless overseer agent-session terminal
# dotfiles-test-firejail: disabled
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: overseer-agent-terminal-output-navigation
# dotfiles-test-case: overseer-agent-session-terminal-contract
# dotfiles-test-case: overseer-agent-output-scheduler-contract
# dotfiles-test-case: ansible-task-picker-preserves-source-window-for-output
# dotfiles-test-case: overseer-dispose-removes-visible-output-buffer
# dotfiles-test-case: codex-new-session-focuses-task-terminal-from-overseer-terminal
# dotfiles-test-case: codex-new-session-from-shell-fence-uses-fence-as-alternate
# dotfiles-test-case: codex-resume-missing-session-cwd-uses-current-cwd
# dotfiles-test-case: overseer-open-recent-same-agent-task-pastes-visual
# dotfiles-test-case: overseer-open-recent-other-agent-task-pastes-visual
# dotfiles-test-case: overseer-open-recent-other-agent-task-continues-without-visual
# dotfiles-test-case: overseer-open-output-keeps-empty-buffer-as-native-alternate
# dotfiles-test-case: overseer-output-repair-first-alternate-toggle
# dotfiles-test-case: overseer-chained-picker-open-output-keeps-alternate-buffer
# dotfiles-test-case: codex-new-visual-selection-pastes-snippet

# Purpose: Guard the agent-session terminal behavior debugged around Overseer output buffers.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-agent-terminals.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-agent-terminals.XXXXXX")
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

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

case "${DOTFILES_TEST_CASE:-}" in
overseer-agent-terminal-output-navigation)
    lua_file="${DOTFILES_TEST_TMP}/overseer-agent-terminal-output-navigation.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  local source_winid = vim.api.nvim_get_current_win()' \
        '  local term_bufnr = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(term_bufnr)' \
        '  local job = vim.fn.termopen({ "sh", "-c", "sleep 2" })' \
        '  assert(job > 0, "termopen failed")' \
        '  vim.api.nvim_set_current_buf(source_bufnr)' \
        '  local session_id = "019e97c4-656e-7c53-b809-8d8a1efbd70c"' \
        '  local task = { id = 1234, name = "codex: demo task with a very long title", metadata = {}, get_bufnr = function() return term_bufnr end }' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return { get = function(id) return id == task.id and task or nil end }' \
        '  end' \
        '  vim.b[term_bufnr].overseer_task = task.id' \
        '  utils.schedule_open_overseer_task_output(task, { winid = source_winid })' \
        '  local opened = vim.wait(1000, function() return vim.api.nvim_get_current_buf() == term_bufnr end, 10)' \
        '  assert(opened, "scheduler did not open the task terminal buffer")' \
        '  assert(vim.bo[term_bufnr].buflisted, "task terminal output should be buflisted")' \
        '  local task_bufname = vim.api.nvim_buf_get_name(term_bufnr)' \
        '  assert(task_bufname == "task://codex: demo task with a very long title", task_bufname)' \
        '  assert(not task_bufname:find("overseer-1234", 1, true), task_bufname)' \
        '  assert(not task_bufname:find("overseer-task://", 1, true), task_bufname)' \
        '  task.name = "run-ansible-playbook 175-setup-dependency-update-tools.archlinux with additional suffix"' \
        '  utils.attach_overseer_task_output_navigation(term_bufnr)' \
        '  task_bufname = vim.api.nvim_buf_get_name(term_bufnr)' \
        '  assert(task_bufname == "task://run-ansible-playbook 175-setup-dependency...", task_bufname)' \
        '  task.metadata.agent_session_id = session_id' \
        '  utils.attach_overseer_task_output_navigation(term_bufnr)' \
        '  task_bufname = vim.api.nvim_buf_get_name(term_bufnr)' \
        '  assert(task_bufname == "task://" .. session_id, task_bufname)' \
        '  assert(not task_bufname:find(task.name, 1, true), task_bufname)' \
        '  assert(vim.b[term_bufnr].overseer_output_navigation_attached == true, "output navigation marker missing")' \
        '  local function map_for(mode, lhs)' \
        '    for _, map in ipairs(vim.api.nvim_buf_get_keymap(term_bufnr, mode)) do' \
        '      if map.lhs == lhs then return map end' \
        '    end' \
        '  end' \
        '  local terminal_exit = map_for("t", "<C-G>")' \
        '  local terminal_exit_rhs = terminal_exit and terminal_exit.rhs:lower() or ""' \
        '  assert(terminal_exit_rhs:find("<c-n>", 1, true) and terminal_exit_rhs:find("stopinsert", 1, true), vim.inspect(terminal_exit))' \
        '  for _, lhs in ipairs({ "<M-j>", "<M-k>" }) do' \
        '    local map = map_for("t", lhs)' \
        '    assert(map, "missing terminal map " .. lhs)' \
        '    local rhs = map.rhs:lower()' \
        '    assert(rhs:find("<c-n>", 1, true) and rhs:find("stopinsert", 1, true), map.rhs)' \
        '    assert(map.rhs:find("open_adjacent_overseer_task_output", 1, true), map.rhs)' \
        '  end' \
        '  assert(not map_for("n", "<C-6>"), "Overseer output should not override native <C-6>")' \
        '  assert(not map_for("n", "<C-^>"), "Overseer output should not override native <C-^>")' \
        '  assert(not map_for("t", "<C-6>"), "Overseer output should not override terminal <C-6>")' \
        '  assert(not map_for("t", "<C-^>"), "Overseer output should not override terminal <C-^>")' \
        '  assert(map_for("n", "<M-j>"), "missing normal-mode next task map")' \
        '  assert(map_for("n", "<M-k>"), "missing normal-mode previous task map")' \
        '  vim.fn.jobstop(job)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-agent-session-terminal-contract)
    lua_file="${DOTFILES_TEST_TMP}/overseer-agent-session-terminal-contract.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local path = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/agent_sessions.lua"' \
        '  local text = table.concat(vim.fn.readfile(path), "\n")' \
        '  assert(text:find([[codex_args("resume", "--no-alt-screen", "-C", session.cwd, session.id)]], 1, true) ~= nil, "Codex resume must keep --no-alt-screen")' \
        '  assert(text:find([[name = "gemini"]], 1, true) ~= nil, "Gemini provider must be registered")' \
        '  assert(text:find([[vim.list_extend(args, { "--session-id", session_id })]], 1, true) ~= nil, "Gemini new sessions should accept preallocated session ids")' \
        '  assert(text:find([[resume_args = function(session) return { "--resume", session.id } end]], 1, true) ~= nil, "Gemini resume should use --resume <id>")' \
        '  assert(not text:find("startinsert", 1, true), "agent sessions should not force permanent terminals into insert mode")' \
        '  assert(not text:find("start_task", 1, true), "do not reintroduce the failed synchronous start_task flow")' \
        '  assert(not text:find("utils.open_overseer_task_output", 1, true), "agent sessions should use the scheduler helper, not a synchronous output opener")' \
        '  assert(not text:find("prepare_task_start_window", 1, true), "agent sessions should not swap the source window through scratch buffers")' \
        '  assert(not text:find("alternate_bufnr", 1, true), "agent sessions should rely on normal buffer history instead of synthetic alternates")' \
        '  assert(text:find("local function start_and_open_task_output", 1, true) ~= nil, "agent sessions should focus output after task:start()")' \
        '  assert(text:find("utils.schedule_open_overseer_task_output(task, { winid = start_win })", 1, true) ~= nil, "started task output should be focused in the source window")' \
        '  assert(text:find("open_task(provider, task, prompt, { wait_for_ready = true, start_win = start_win, open_output = false })", 1, true) ~= nil, "new/resumed tasks should delay output focus until after start")' \
        '  assert(text:find("if not start_and_open_task_output(provider, task, start_win) then return end", 1, true) ~= nil, "new task flow should open only after a successful start")' \
        '  assert(text:find("vim%.cmd%.stopinsert") ~= nil, "terminal cleanup must use stopinsert")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-agent-output-scheduler-contract)
    lua_file="${DOTFILES_TEST_TMP}/overseer-agent-output-scheduler-contract.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils_path = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/utils.lua"' \
        '  local remap_path = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/remap.lua"' \
        '  local utils_text = table.concat(vim.fn.readfile(utils_path), "\n")' \
        '  local remap_text = table.concat(vim.fn.readfile(remap_path), "\n")' \
        '  local output_navigation_start = assert(utils_text:find("function M.attach_overseer_task_output_navigation", 1, true))' \
        '  local output_navigation_end = assert(utils_text:find("function M.open_started_overseer_task_output", output_navigation_start, true))' \
        '  local output_navigation_text = utils_text:sub(output_navigation_start, output_navigation_end)' \
        '  assert(not utils_text:find("_create_terminal", 1, true), "scheduler must not call Overseer private terminal APIs")' \
        '  assert(not utils_text:find("function M.open_overseer_task_output", 1, true), "do not reintroduce the failed synchronous output helper")' \
        '  assert(not output_navigation_text:find("ModeChanged", 1, true), "do not rely on ModeChanged terminal-mode cleanup for agent outputs")' \
        '  assert(not output_navigation_text:find("<C-6>", 1, true), "Overseer outputs should rely on native <C-6> behavior")' \
        '  assert(not output_navigation_text:find("<C-^>", 1, true), "Overseer outputs should rely on native <C-^> behavior")' \
        '  assert(not utils_text:find("function M.open_alternate_buffer", 1, true), "do not add a parallel alternate-buffer opener")' \
        '  assert(not utils_text:find("terminal_alternate_buffer_rhs", 1, true), "do not map terminal alternate-buffer switching")' \
        '  assert(not utils_text:find("overseer_output_alternate_bufnr", 1, true), "do not keep a parallel alternate-buffer state for Overseer outputs")' \
        '  assert(not utils_text:find([[desc = "Attach task terminal keymaps"]], 1, true), "task keymaps should attach once when the terminal exists, not on every BufEnter")' \
        '  assert(utils_text:find("vim%.bo%[bufnr%]%.buflisted = true") ~= nil, "task outputs should stay buflisted")' \
        '  assert(utils_text:find("pcall%(vim%.cmd%.buffer, bufnr%)") ~= nil, "task outputs should be opened with :buffer so # remains natural")' \
        '  assert(utils_text:find("task:get_bufnr%(%)") ~= nil, "scheduler should use the public task buffer accessor")' \
        '  assert(utils_text:find("<C%-\\\\><C%-n><Cmd>stopinsert<CR>", 1, false) ~= nil, "terminal buffer maps must clear stopinsert")' \
        '  assert(remap_text:find("<C%-\\\\><C%-n><Cmd>stopinsert<CR>", 1, false) ~= nil, "global terminal exit map must clear stopinsert")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
ansible-task-picker-preserves-source-window-for-output)
    lua_file="${DOTFILES_TEST_TMP}/ansible-task-picker-preserves-source-window-for-output.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local cachectl = vim.env.DOTFILES_TEST_TMP .. "/cachectl"' \
        '  vim.fn.writefile({' \
        '    "#!/bin/sh",' \
        '    "set -eu",' \
        '    "case \"$1\" in",' \
        '    "  get) printf '\''{\"version\":1,\"source_mtime\":9999999999,\"public_items\":[\"20-10 : Demo task\"]}\\n'\'' ;;",' \
        '    "  *) exit 0 ;;",' \
        '    "esac",' \
        '  }, cachectl)' \
        '  vim.fn.setfperm(cachectl, "rwxr-xr-x")' \
        '  vim.env.CACHECTL_BIN = cachectl' \
        '  package.preload["overseer.template.system-tasks.TASK__run_ansible_playbook"] = function() return { name = "run-ansible-playbook" } end' \
        '  local scheduled_task' \
        '  local scheduled_opts' \
        '  local utils = require("serranomorante.utils")' \
        '  utils.attach_keymaps = function() end' \
        '  utils.schedule_open_overseer_task_output = function(task, opts)' \
        '    scheduled_task = task' \
        '    scheduled_opts = opts' \
        '  end' \
        '  local source_winid = vim.api.nvim_get_current_win()' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  local callback_winid' \
        '  package.loaded["overseer"] = {' \
        '    run_task = function(_, callback)' \
        '      callback_winid = vim.api.nvim_get_current_win()' \
        '      callback({ id = 42, get_bufnr = function() return nil end })' \
        '    end,' \
        '  }' \
        '  vim.ui.select = function(items, _, on_choice)' \
        '    assert(vim.api.nvim_get_current_win() == source_winid, "picker should be launched from the source window")' \
        '    vim.cmd.vsplit()' \
        '    assert(vim.api.nvim_get_current_win() ~= source_winid, "test should switch away before picker callback")' \
        '    on_choice(items[1])' \
        '  end' \
        '  require("serranomorante.plugins.jobs.ansible_task_picker").select()' \
        '  assert(callback_winid ~= source_winid, "test should run the async callback away from the source window")' \
        '  assert(scheduled_task and scheduled_task.id == 42, "task output was not scheduled")' \
        '  assert(scheduled_opts and scheduled_opts.winid == source_winid, ("expected source winid %d, got %s"):format(source_winid, vim.inspect(scheduled_opts)))' \
        '  assert(vim.api.nvim_win_get_buf(source_winid) == source_bufnr, "source window should still show the source buffer")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-dispose-removes-visible-output-buffer)
    lua_file="${DOTFILES_TEST_TMP}/overseer-dispose-removes-visible-output-buffer.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local callbacks = {}' \
        '  local previous_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(previous_bufnr, "previous-before-dispose-output-buffer-test")' \
        '  local winid = vim.api.nvim_get_current_win()' \
        '  local term_bufnr = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(term_bufnr)' \
        '  local job = vim.fn.termopen({ "sh", "-c", "sleep 2" })' \
        '  assert(job > 0, "termopen failed")' \
        '  local task = {' \
        '    id = 9876,' \
        '    name = "dispose-output-buffer-test",' \
        '    get_bufnr = function() return term_bufnr end,' \
        '    subscribe = function(_, event, callback) callbacks[event] = callback end,' \
        '  }' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return { get = function(id) return id == task.id and task or nil end }' \
        '  end' \
        '  vim.b[term_bufnr].overseer_task = task.id' \
        '  vim.cmd.buffer(previous_bufnr)' \
        '  assert(utils.open_started_overseer_task_output(task, { winid = winid }), "task output was not opened")' \
        '  assert(vim.api.nvim_get_current_buf() == term_bufnr, "task output was not focused")' \
        '  assert(vim.bo[term_bufnr].buflisted, "output should be listed while task exists")' \
        '  assert(callbacks.on_dispose, "dispose cleanup was not attached")' \
        '  pcall(vim.fn.jobstop, job)' \
        '  callbacks.on_dispose(task)' \
        '  assert(vim.fn.bufwinid(term_bufnr) == -1, "disposed output buffer is still visible")' \
        '  if vim.api.nvim_buf_is_valid(term_bufnr) then' \
        '    assert(not vim.bo[term_bufnr].buflisted, "disposed output buffer is still buflisted")' \
        '  end' \
        '  assert(vim.api.nvim_get_current_buf() == previous_bufnr, "dispose should return to the buffer that the task output replaced")' \
        '  assert(vim.bo[previous_bufnr].buftype ~= "nofile", "dispose should not return to a scratch buffer")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-new-session-focuses-task-terminal-from-overseer-terminal)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

case " $* " in
*" ids "*)
    printf '{"version":1,"provider":"codex","ids":[]}\n'
    ;;
*" watch-new "*)
    printf '{"version":1,"provider":"codex","event":"timeout"}\n'
    ;;
*)
    printf '{"version":1,"provider":"codex","sessions":[]}\n'
    ;;
esac
SH
    cat >"${fake_bin}/codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-new-session-focuses-task-terminal-from-overseer-terminal.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  local source_winid = vim.api.nvim_get_current_win()' \
        '  local old_bufnr = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(old_bufnr)' \
        '  local old_job = vim.fn.termopen({ "sh", "-c", "sleep 10" })' \
        '  assert(old_job > 0, "old termopen failed")' \
        '  vim.b[old_bufnr].overseer_task = 99999' \
        '  require("serranomorante.plugins.jobs.agent_sessions").open_new("codex")' \
        '  local focused = vim.wait(5000, function()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return vim.api.nvim_get_current_win() == source_winid' \
        '      and bufnr ~= old_bufnr' \
        '      and vim.bo[bufnr].buftype == "terminal"' \
        '      and vim.b[bufnr].overseer_task ~= nil' \
        '      and vim.b[bufnr].overseer_output_navigation_attached == true' \
        '  end, 20)' \
        '  assert(focused, "new Codex task terminal was not focused from the existing Overseer terminal")' \
        '  local new_bufnr = vim.api.nvim_get_current_buf()' \
        '  assert(vim.bo[new_bufnr].buflisted, "new task terminal should be buflisted")' \
        '  assert(vim.fn.bufnr("#") == old_bufnr, ("expected alternate buffer %d, got %d"):format(old_bufnr, vim.fn.bufnr("#")))' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == old_bufnr end, 10), "<C-6> did not return to the previous Overseer terminal")' \
        '  assert(vim.fn.bufnr("#") == new_bufnr, ("expected new task as alternate buffer %d, got %d"):format(new_bufnr, vim.fn.bufnr("#")))' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == new_bufnr end, 10), "<C-6> did not return to the new Overseer terminal")' \
        '  assert(vim.fn.bufnr("#") == old_bufnr, ("expected previous task as alternate buffer %d, got %d"):format(old_bufnr, vim.fn.bufnr("#")))' \
        '  pcall(vim.fn.jobstop, old_job)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-new-session-from-shell-fence-uses-fence-as-alternate)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

case " $* " in
*" ids "*)
    printf '{"version":1,"provider":"codex","ids":[]}\n'
    ;;
*" watch-new "*)
    printf '{"version":1,"provider":"codex","event":"timeout"}\n'
    ;;
*)
    printf '{"version":1,"provider":"codex","sessions":[]}\n'
    ;;
esac
SH
    cat >"${fake_bin}/codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-new-session-from-shell-fence-uses-fence-as-alternate.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  vim.bo.filetype = "markdown"' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "```sh", "sleep 10", "```" })' \
        '  vim.api.nvim_win_set_cursor(0, { 2, 0 })' \
        '  require("serranomorante.utils").run_shell_fence()' \
        '  local fenced_focused = vim.wait(5000, function()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return vim.bo[bufnr].buftype == "terminal" and vim.b[bufnr].overseer_task ~= nil' \
        '  end, 20)' \
        '  assert(fenced_focused, "shell fence task terminal was not focused")' \
        '  local fence_bufnr = vim.api.nvim_get_current_buf()' \
        '  require("serranomorante.plugins.jobs.agent_sessions").open_new("codex")' \
        '  local codex_focused = vim.wait(5000, function()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return bufnr ~= fence_bufnr' \
        '      and vim.bo[bufnr].buftype == "terminal"' \
        '      and vim.b[bufnr].overseer_task ~= nil' \
        '      and vim.b[bufnr].overseer_output_navigation_attached == true' \
        '  end, 20)' \
        '  assert(codex_focused, "new Codex task terminal was not focused from shell fence task")' \
        '  local codex_bufnr = vim.api.nvim_get_current_buf()' \
        '  assert(vim.fn.bufnr("#") == fence_bufnr, ("expected shell fence %d as alternate, got %d"):format(fence_bufnr, vim.fn.bufnr("#")))' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == fence_bufnr end, 10), "first native <C-6> did not return to the shell fence task")' \
        '  assert(vim.fn.bufnr("#") == codex_bufnr, ("expected Codex task %d as alternate after first toggle, got %d"):format(codex_bufnr, vim.fn.bufnr("#")))' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-resume-missing-session-cwd-uses-current-cwd)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    missing_cwd="${DOTFILES_TEST_TMP}/missing-cwd"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

provider=
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done

case " ${provider} $* " in
*" codex "*)
    printf '{"version":1,"provider":"codex","sessions":[{"provider":"codex","path":"%s/session.jsonl","id":"resume-missing-cwd-session","cwd":"%s","timestamp":"2026-06-17T14:51:10Z","updated_at":"2026-06-17T15:03:39Z","title":"missing cwd session"}]}\n' "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_MISSING_CWD}"
    ;;
*)
    printf '{"version":1,"provider":"%s","sessions":[]}\n' "${provider:-claude}"
    ;;
esac
SH
    cat >"${fake_bin}/codex" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$PWD" >"${DOTFILES_TEST_TMP}/codex-resume-pwd"
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/codex-resume-args"
printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-resume-missing-session-cwd-uses-current-cwd.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local session_id = "resume-missing-cwd-session"' \
        '  local valid_cwd = vim.env.DOTFILES_TEST_TMP .. "/valid-cwd"' \
        '  local missing_cwd = vim.env.DOTFILES_TEST_MISSING_CWD' \
        '  vim.fn.mkdir(valid_cwd, "p")' \
        '  assert(vim.fn.isdirectory(missing_cwd) == 0, "test fixture cwd should not exist: " .. missing_cwd)' \
        '  vim.cmd.cd(vim.fn.fnameescape(valid_cwd))' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  require("serranomorante.plugins.jobs.agent_sessions").keys()' \
        '  vim.cmd("AgentResumeById " .. session_id)' \
        '  local matching_task' \
        '  local running = vim.wait(5000, function()' \
        '    for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '      local metadata = task.metadata or {}' \
        '      local cmd = type(task.cmd) == "string" and task.cmd or ""' \
        '      if metadata.agent_session_id == session_id or cmd:find(session_id, 1, true) then' \
        '        matching_task = task' \
        '        if task.status == require("overseer.constants").STATUS.RUNNING then return true end' \
        '      end' \
        '    end' \
        '    return false' \
        '  end, 20)' \
        '  assert(running and matching_task, "resumed task did not start")' \
        '  assert(matching_task.cwd == valid_cwd, ("expected task cwd %s, got %s"):format(valid_cwd, tostring(matching_task.cwd)))' \
        '  local cmd = type(matching_task.cmd) == "string" and matching_task.cmd or table.concat(vim.tbl_map(tostring, matching_task.cmd or {}), " ")' \
        '  assert(cmd:find("-C " .. valid_cwd, 1, true), cmd)' \
        '  assert(not cmd:find(missing_cwd, 1, true), cmd)' \
        '  local process_started = vim.wait(2000, function() return vim.fn.filereadable(vim.env.DOTFILES_TEST_TMP .. "/codex-resume-pwd") == 1 end, 20)' \
        '  assert(process_started, "fake codex resume process did not start")' \
        '  local process_cwd = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/codex-resume-pwd"), "\n")' \
        '  local process_args = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/codex-resume-args"), "\n")' \
        '  assert(process_cwd == valid_cwd, ("expected process cwd %s, got %s"):format(valid_cwd, process_cwd))' \
        '  assert(process_args:find("-C " .. valid_cwd, 1, true), process_args)' \
        '  assert(not process_args:find(missing_cwd, 1, true), process_args)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    local metadata = task.metadata or {}' \
        '    if metadata.agent_session_id == session_id or (type(task.cmd) == "string" and task.cmd:find(session_id, 1, true)) then' \
        '      assert(task.status ~= require("overseer.constants").STATUS.PENDING, "resume left a matching task in PENDING")' \
        '    end' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    DOTFILES_TEST_MISSING_CWD="$missing_cwd" run_nvim_lua_file "$lua_file"
    ;;
overseer-open-recent-same-agent-task-pastes-visual)
    lua_file="${DOTFILES_TEST_TMP}/overseer-open-recent-same-agent-task-pastes-visual.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.bo.filetype = "lua"' \
        '  vim.api.nvim_buf_set_name(source_bufnr, "task://current-agent-session")' \
        '  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "selected_alpha()", "selected_beta()" })' \
        '  vim.fn.setpos([['\''<]], { source_bufnr, 1, 1, 0 })' \
        '  vim.fn.setpos([['\''>]], { source_bufnr, 2, 15, 0 })' \
        '  local current_task = {' \
        '    id = 7,' \
        '    name = "codex current",' \
        '    time_start = 10,' \
        '    status = "RUNNING",' \
        '    metadata = { agent_provider = "codex", agent_session_id = "current-session" },' \
        '  }' \
        '  vim.b[source_bufnr].overseer_task = current_task.id' \
        '  local opened_task' \
        '  local opened_prompt' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return {' \
        '      list_tasks = function() return { current_task } end,' \
        '      get = function(id) return id == current_task.id and current_task or nil end,' \
        '      sort_finished_recently = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.action_util"] = nil' \
        '  package.preload["overseer.action_util"] = function() return { run_task_action = function() error("same agent task should receive prompt instead of plain open action") end } end' \
        '  local agent_sessions = require("serranomorante.plugins.jobs.agent_sessions")' \
        '  agent_sessions.open_task_with_prompt = function(task, prompt)' \
        '    opened_task = task' \
        '    opened_prompt = prompt' \
        '    return true' \
        '  end' \
        '  vim.ui.select = function(items, _, on_choice)' \
        '    assert(#items == 1, vim.inspect(items))' \
        '    on_choice(items[1])' \
        '  end' \
        '  require("serranomorante.plugins.jobs.overseer_task_actions").open_recent_task({ visual = true })' \
        '  assert(opened_task == current_task, "same task was not opened through agent prompt path")' \
        '  assert(type(opened_prompt) == "string" and opened_prompt:find("selected_alpha%(%)") and opened_prompt:find("selected_beta%(%)"), opened_prompt)' \
        '  assert(opened_prompt:find("```lua", 1, true), opened_prompt)' \
        '  assert(not opened_prompt:find("continuing this ", 1, true), opened_prompt)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-open-recent-other-agent-task-pastes-visual)
    lua_file="${DOTFILES_TEST_TMP}/overseer-open-recent-other-agent-task-pastes-visual.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.bo.filetype = "lua"' \
        '  vim.api.nvim_buf_set_name(source_bufnr, "task://source-agent-session")' \
        '  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, { "selected_gamma()", "selected_delta()" })' \
        '  vim.fn.setpos([['\''<]], { source_bufnr, 1, 1, 0 })' \
        '  vim.fn.setpos([['\''>]], { source_bufnr, 2, 16, 0 })' \
        '  local source_task = {' \
        '    id = 21,' \
        '    name = "claude source",' \
        '    time_start = 20,' \
        '    status = "RUNNING",' \
        '    metadata = { agent_provider = "claude", agent_session_id = "source-session" },' \
        '  }' \
        '  local target_task = {' \
        '    id = 22,' \
        '    name = "codex target",' \
        '    time_start = 30,' \
        '    status = "RUNNING",' \
        '    metadata = { agent_provider = "codex", agent_session_id = "target-session" },' \
        '  }' \
        '  vim.b[source_bufnr].overseer_task = source_task.id' \
        '  local opened_task' \
        '  local opened_prompt' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return {' \
        '      list_tasks = function() return { target_task, source_task } end,' \
        '      get = function(id)' \
        '        if id == source_task.id then return source_task end' \
        '        if id == target_task.id then return target_task end' \
        '      end,' \
        '      sort_finished_recently = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.action_util"] = nil' \
        '  package.preload["overseer.action_util"] = function() return { run_task_action = function() error("other agent task with visual selection should receive prompt instead of plain open action") end } end' \
        '  local agent_sessions = require("serranomorante.plugins.jobs.agent_sessions")' \
        '  agent_sessions.open_task_with_prompt = function(task, prompt)' \
        '    opened_task = task' \
        '    opened_prompt = prompt' \
        '    return true' \
        '  end' \
        '  vim.ui.select = function(items, _, on_choice)' \
        '    assert(#items == 2, vim.inspect(items))' \
        '    on_choice(items[1])' \
        '  end' \
        '  require("serranomorante.plugins.jobs.overseer_task_actions").open_recent_task({ visual = true })' \
        '  assert(opened_task == target_task, "target task was not opened through agent prompt path")' \
        '  assert(type(opened_prompt) == "string" and opened_prompt:find("selected_gamma%(%)") and opened_prompt:find("selected_delta%(%)"), opened_prompt)' \
        '  assert(opened_prompt:find("```lua", 1, true), opened_prompt)' \
        '  assert(not opened_prompt:find("continuing this ", 1, true), opened_prompt)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-open-recent-other-agent-task-continues-without-visual)
    lua_file="${DOTFILES_TEST_TMP}/overseer-open-recent-other-agent-task-continues-without-visual.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(source_bufnr, "task://source-agent-session")' \
        '  local source_task = {' \
        '    id = 11,' \
        '    name = "claude source",' \
        '    time_start = 20,' \
        '    status = "RUNNING",' \
        '    metadata = { agent_provider = "claude", agent_session_id = "source-session" },' \
        '  }' \
        '  local target_task = {' \
        '    id = 12,' \
        '    name = "codex target",' \
        '    time_start = 30,' \
        '    status = "RUNNING",' \
        '    metadata = { agent_provider = "codex", agent_session_id = "target-session" },' \
        '  }' \
        '  vim.b[source_bufnr].overseer_task = source_task.id' \
        '  local opened_task' \
        '  local opened_prompt' \
        '  package.loaded["overseer.task_list"] = nil' \
        '  package.preload["overseer.task_list"] = function()' \
        '    return {' \
        '      list_tasks = function() return { target_task, source_task } end,' \
        '      get = function(id)' \
        '        if id == source_task.id then return source_task end' \
        '        if id == target_task.id then return target_task end' \
        '      end,' \
        '      sort_finished_recently = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.action_util"] = nil' \
        '  package.preload["overseer.action_util"] = function() return { run_task_action = function() error("other agent task should receive continuation prompt instead of plain open action") end } end' \
        '  local agent_sessions = require("serranomorante.plugins.jobs.agent_sessions")' \
        '  agent_sessions.open_task_with_prompt = function(task, prompt)' \
        '    opened_task = task' \
        '    opened_prompt = prompt' \
        '    return true' \
        '  end' \
        '  vim.ui.select = function(items, _, on_choice)' \
        '    assert(#items == 2, vim.inspect(items))' \
        '    on_choice(items[1])' \
        '  end' \
        '  require("serranomorante.plugins.jobs.overseer_task_actions").open_recent_task()' \
        '  assert(opened_task == target_task, "target task was not opened through agent prompt path")' \
        '  assert(type(opened_prompt) == "string" and opened_prompt:find("continuing this claude conversation with id: source%-session"), opened_prompt)' \
        '  assert(not opened_prompt:find("```", 1, true), opened_prompt)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-open-output-keeps-empty-buffer-as-native-alternate)
    lua_file="${DOTFILES_TEST_TMP}/overseer-open-output-keeps-empty-buffer-as-native-alternate.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    output = { use_terminal = true, preserve_output = true },' \
        '    component_aliases = { default = { "on_exit_set_status" } },' \
        '  })' \
        '  local empty_bufnr = vim.api.nvim_get_current_buf()' \
        '  assert(vim.api.nvim_buf_get_name(empty_bufnr) == "", "test should start from an unnamed empty buffer")' \
        '  local task = require("overseer").new_task({ name = "empty-buffer-alt-test", cmd = { "sh", "-c", "sleep 10" } })' \
        '  task:start()' \
        '  assert(vim.wait(3000, function() return task:get_bufnr() ~= nil end, 10), "task terminal was not created")' \
        '  local task_bufnr = assert(task:get_bufnr())' \
        '  task:open_output()' \
        '  require("serranomorante.utils").attach_overseer_task_output_navigation(task_bufnr)' \
        '  assert(vim.api.nvim_get_current_buf() == task_bufnr, "task output was not opened")' \
        '  assert(vim.fn.bufnr("#") == empty_bufnr, ("expected empty buffer %d as alternate, got %d"):format(empty_bufnr, vim.fn.bufnr("#")))' \
        '  for _, map in ipairs(vim.api.nvim_buf_get_keymap(task_bufnr, "n")) do' \
        '    assert(map.lhs ~= "<C-6>" and map.lhs ~= "<C-^>", "task output should not map native alternate-buffer keys")' \
        '  end' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == empty_bufnr end, 10), "native <C-6> did not return to the empty buffer")' \
        '  assert(vim.fn.bufnr("#") == task_bufnr, ("expected task buffer %d as alternate after return, got %d"):format(task_bufnr, vim.fn.bufnr("#")))' \
        '  pcall(function() task:dispose(true) end)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-output-repair-first-alternate-toggle)
    lua_file="${DOTFILES_TEST_TMP}/overseer-output-repair-first-alternate-toggle.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    output = { use_terminal = true, preserve_output = true },' \
        '    component_aliases = { default = { "on_exit_set_status" } },' \
        '  })' \
        '  local utils = require("serranomorante.utils")' \
        '  local source_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(source_bufnr, "source-before-scheduled-overseer-output")' \
        '  local source_winid = vim.api.nvim_get_current_win()' \
        '  local task = require("overseer").new_task({ name = "scheduled-output-alt-test", cmd = { "sh", "-c", "sleep 10" } })' \
        '  utils.remember_overseer_output_previous_buffer(source_winid)' \
        '  task:start()' \
        '  assert(vim.wait(3000, function() return task:get_bufnr() ~= nil end, 10), "task terminal was not created")' \
        '  local task_bufnr = assert(task:get_bufnr())' \
        '  local clobbered = false' \
        '  vim.schedule(function()' \
        '    if vim.api.nvim_get_current_buf() ~= task_bufnr then return end' \
        '    vim.cmd.buffer(source_bufnr)' \
        '    vim.cmd("keepalt buffer " .. task_bufnr)' \
        '    clobbered = true' \
        '  end)' \
        '  assert(utils.open_started_overseer_task_output(task, { winid = source_winid }), "task output was not opened")' \
        '  assert(vim.wait(3000, function() return clobbered and vim.api.nvim_get_current_buf() == task_bufnr and vim.fn.bufnr("#") == source_bufnr end, 10), ("output repair did not preserve native alternate buffer after clobber: current=%d task=%d alternate=%d source=%d clobbered=%s"):format(vim.api.nvim_get_current_buf(), task_bufnr, vim.fn.bufnr("#"), source_bufnr, tostring(clobbered)))' \
        '  for _, map in ipairs(vim.api.nvim_buf_get_keymap(task_bufnr, "n")) do' \
        '    assert(map.lhs ~= "<C-6>" and map.lhs ~= "<C-^>", "task output should not map native alternate-buffer keys")' \
        '  end' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == source_bufnr end, 10), "first native <C-6> did not return to the source buffer")' \
        '  assert(vim.fn.bufnr("#") == task_bufnr, ("expected task buffer %d as alternate after first toggle, got %d"):format(task_bufnr, vim.fn.bufnr("#")))' \
        '  pcall(function() task:dispose(true) end)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-chained-picker-open-output-keeps-alternate-buffer)
    lua_file="${DOTFILES_TEST_TMP}/overseer-chained-picker-open-output-keeps-alternate-buffer.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    output = { use_terminal = true, preserve_output = true },' \
        '    component_aliases = { default = { "on_exit_set_status" } },' \
        '  })' \
        '  local utils = require("serranomorante.utils")' \
        '  local previous_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(previous_bufnr, "alternate-before-overseer-picker")' \
        '  local source_bufnr = vim.api.nvim_create_buf(true, true)' \
        '  vim.api.nvim_buf_set_name(source_bufnr, "source-before-overseer-picker")' \
        '  vim.cmd.buffer(source_bufnr)' \
        '  local task = require("overseer").new_task({ name = "picker-open-output-alt-test", cmd = { "sh", "-c", "sleep 10" } })' \
        '  task:start()' \
        '  assert(vim.wait(3000, function() return task:get_bufnr() ~= nil end, 10), "task terminal was not created")' \
        '  local task_bufnr = assert(task:get_bufnr())' \
        '  utils.fzf({' \
        '    source = { "1: task" },' \
        '    options = { "--filter=1" },' \
        '    sink = function()' \
        '      utils.fzf({' \
        '        source = { "1: open" },' \
        '        options = { "--filter=1" },' \
        '        sink = function()' \
        '          task:open_output()' \
        '          utils.attach_overseer_task_output_navigation(task_bufnr)' \
        '        end,' \
        '      })' \
        '    end,' \
        '  })' \
        '  assert(vim.wait(5000, function() return vim.api.nvim_get_current_buf() == task_bufnr end, 20), "task output was not opened from chained pickers")' \
        '  assert(vim.fn.bufnr("#") == source_bufnr, ("expected source buffer %d as alternate, got %d"):format(source_bufnr, vim.fn.bufnr("#")))' \
        '  for _, map in ipairs(vim.api.nvim_buf_get_keymap(task_bufnr, "n")) do' \
        '    assert(map.lhs ~= "<C-6>" and map.lhs ~= "<C-^>", "task output should not map native alternate-buffer keys")' \
        '  end' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == source_bufnr end, 10), "<C-6> did not return to the source buffer")' \
        '  assert(vim.fn.bufnr("#") == task_bufnr, ("expected task buffer %d as alternate, got %d"):format(task_bufnr, vim.fn.bufnr("#")))' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-^>", true, false, true), "x", false)' \
        '  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() == task_bufnr end, 10), "<C-6> did not return to the picker-opened task output")' \
        '  assert(vim.fn.bufnr("#") == source_bufnr, ("expected source buffer %d as alternate after second toggle, got %d"):format(source_bufnr, vim.fn.bufnr("#")))' \
        '  local leaked_fzf_buffers = vim.tbl_filter(function(bufnr)' \
        '    return vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "fzf"' \
        '  end, vim.api.nvim_list_bufs())' \
        '  assert(#leaked_fzf_buffers == 0, "closed fzf picker buffers should be wiped, got " .. vim.inspect(leaked_fzf_buffers))' \
        '  pcall(function() task:dispose(true) end)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-new-visual-selection-pastes-snippet)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

case " $* " in
*" ids "*)
    printf '{"version":1,"provider":"codex","ids":[]}\n'
    ;;
*" watch-new "*)
    printf '{"version":1,"provider":"codex","event":"timeout"}\n'
    ;;
*)
    printf '{"version":1,"provider":"codex","sessions":[]}\n'
    ;;
esac
SH
    cat >"${fake_bin}/codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
while IFS= read -r line; do
    printf '%s\n' "$line" >>"${DOTFILES_TEST_TMP}/codex-stdin"
done
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-new-visual-selection-pastes-snippet.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  vim.g.mapleader = " "' \
        '  require("serranomorante.plugins.jobs.agent_sessions").keys()' \
        '  local source_path = vim.env.DOTFILES_TEST_TMP .. "/source.lua"' \
        '  vim.fn.writefile({ "selected_alpha()", "selected_beta()" }, source_path)' \
        '  vim.cmd.edit(source_path)' \
        '  vim.bo.filetype = "lua"' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ggVG cn", true, false, true), "x", false)' \
        '  local stdin_path = vim.env.DOTFILES_TEST_TMP .. "/codex-stdin"' \
        '  local pasted = vim.wait(5000, function()' \
        '    if vim.fn.filereadable(stdin_path) ~= 1 then return false end' \
        '    local text = table.concat(vim.fn.readfile(stdin_path), "\n")' \
        '    return text:find("selected_alpha%(%)") and text:find("selected_beta%(%)") and text:find("```lua", 1, true)' \
        '  end, 20)' \
        '  assert(pasted, vim.fn.filereadable(stdin_path) == 1 and table.concat(vim.fn.readfile(stdin_path), "\n") or "codex stdin was not written")' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
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
