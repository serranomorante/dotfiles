#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless overseer agent-session terminal
# dotfiles-test-firejail: disabled
# dotfiles-test-case: overseer-agent-terminal-output-navigation
# dotfiles-test-case: opencode-output-uses-readable-ansi-black
# dotfiles-test-case: overseer-agent-session-terminal-contract
# dotfiles-test-case: overseer-agent-output-scheduler-contract
# dotfiles-test-case: ansible-task-picker-preserves-source-window-for-output
# dotfiles-test-case: overseer-dispose-removes-visible-output-buffer
# dotfiles-test-case: codex-new-session-focuses-task-terminal-from-overseer-terminal
# dotfiles-test-case: codex-new-session-does-not-wait-for-session-id-scan
# dotfiles-test-case: codex-new-session-from-shell-fence-uses-fence-as-alternate
# dotfiles-test-case: codex-resume-missing-session-cwd-uses-current-cwd
# dotfiles-test-case: overseer-open-recent-same-agent-task-pastes-visual
# dotfiles-test-case: overseer-open-recent-other-agent-task-pastes-visual
# dotfiles-test-case: overseer-open-recent-other-agent-task-continues-without-visual
# dotfiles-test-case: overseer-open-output-keeps-empty-buffer-as-native-alternate
# dotfiles-test-case: overseer-output-repair-first-alternate-toggle
# dotfiles-test-case: overseer-chained-picker-open-output-keeps-alternate-buffer
# dotfiles-test-case: codex-new-visual-selection-pastes-snippet
# dotfiles-test-case: codex-new-renames-pending-tmux-session-after-session-id
# dotfiles-test-case: sub-agent-new-session-uses-role-aware-tmux-name
# dotfiles-test-case: codex-resume-ignores-cached-pending-tmux-session
# dotfiles-test-case: codex-resume-unsandboxed-uses-direct-executable
# dotfiles-test-case: agent-tmux-socket-dirs-are-private
# dotfiles-test-case: agent-tasks-dispose-kills-tmux-session
# dotfiles-test-case: agent-tasks-detach-from-sandbox-resumes-codex-unsandboxed
# dotfiles-test-case: overseer-actions-include-dispose-and-kill-tmux
# dotfiles-test-case: agent-tasks-reconcile-opens-missing-tmux-sessions
# dotfiles-test-case: refresh-terminal-window-resizes-agent-tmux

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
        '  assert(task_bufname == "task://019e97", task_bufname)' \
        '  assert(not task_bufname:find(task.name, 1, true), task_bufname)' \
        '  assert(vim.b[term_bufnr].overseer_output_navigation_attached == true, "output navigation marker missing")' \
        '  local function map_for(mode, lhs)' \
        '    for _, map in ipairs(vim.api.nvim_buf_get_keymap(term_bufnr, mode)) do' \
        '      if map.lhs == lhs then return map end' \
        '    end' \
        '  end' \
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
opencode-output-uses-readable-ansi-black)
    lua_file="${DOTFILES_TEST_TMP}/opencode-output-uses-readable-ansi-black.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local term_bufnr = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(term_bufnr)' \
        '  local job = vim.fn.termopen({ "sh", "-c", "sleep 2" })' \
        '  assert(job > 0, "termopen failed")' \
        '  local task = {' \
        '    id = 4321,' \
        '    name = "opencode: [ses_04] Contrast", ' \
        '    metadata = { agent_provider = "opencode", agent_session_id = "ses_04contrast" },' \
        '    get_bufnr = function() return term_bufnr end,' \
        '  }' \
        '  utils.name_overseer_task_output(task, term_bufnr)' \
        '  assert(vim.api.nvim_buf_get_name(term_bufnr) == "task://MASTER-opencode: [04cont] Contrast", vim.api.nvim_buf_get_name(term_bufnr))' \
        '  assert(vim.b[term_bufnr].terminal_color_0 == "#7d8590", "ANSI black should be readable muted text")' \
        '  assert(vim.b[term_bufnr].terminal_color_4 == "#58a6ff", "ANSI blue should be readable on selected rows")' \
        '  assert(vim.b[term_bufnr].terminal_color_8 == "#8b949e", "bright ANSI black should be readable muted text")' \
        '  assert(vim.b[term_bufnr].terminal_color_12 == "#79c0ff", "bright ANSI blue should be readable on selected rows")' \
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
        '  assert(text:find([[local retry_known_session_ids = provider.name == "codex" and nil or known_session_ids]], 1, true) ~= nil, "Codex fallback linking must ignore possibly contaminated post-start known ids")' \
        '  assert(text:find([[codex_known_session_ids_promise = async_session_ids(provider, cwd)]], 1, true) ~= nil, "Codex session id snapshot should start before task launch")' \
        '  assert(text:find("if not start_and_open_task_output(provider, task, start_win) then return end", 1, true) ~= nil, "new task flow should open only after a successful start")' \
        '  assert(text:find("vim%.cmd%.stopinsert") ~= nil, "terminal cleanup must use stopinsert")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
agent-tmux-socket-dirs-are-private)
    lua_file="${DOTFILES_TEST_TMP}/agent-tmux-socket-dirs-are-private.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local tmpdir = vim.env.DOTFILES_TEST_TMP .. "/agent-tmux-socket-dirs-are-private"' \
        '  vim.fn.delete(tmpdir, "rf")' \
        '  vim.fn.mkdir(tmpdir, "p", 448)' \
        '  vim.env.TMUX_TMPDIR = tmpdir' \
        '  local passwd = assert(vim.uv.os_get_passwd(vim.env.USER or ""), "missing passwd entry")' \
        '  local socket_root = tmpdir .. "/tmux-" .. tostring(passwd.uid)' \
        '  utils.ensure_agent_tmux_socket_dirs("/run/user/" .. tostring(passwd.uid) .. "/nvim.test.sock")' \
        '  for _, path in ipairs({' \
        '    socket_root,' \
        '    socket_root .. "/run",' \
        '    socket_root .. "/run/user",' \
        '    socket_root .. "/run/user/" .. tostring(passwd.uid),' \
        '  }) do' \
        '    assert(vim.fn.isdirectory(path) == 1, "missing tmux socket directory: " .. path)' \
        '    assert(vim.fn.getfperm(path) == "rwx------", path .. " has " .. vim.fn.getfperm(path))' \
        '  end' \
        '  vim.fn.setfperm(socket_root, "rwxr-xr-x")' \
        '  utils.ensure_agent_tmux_socket_dirs("overseer")' \
        '  assert(vim.fn.getfperm(socket_root) == "rwx------", "existing socket root was not repaired")' \
        '  vim.fn.delete(tmpdir, "rf")' \
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
        '  package.preload["overseer.template.system-tasks.TASK__run_ansible_playbook"] = function() return { name = "run-ansible-playbook", params = { task_id = { type = "string" }, pass = { type = "string" } } } end' \
        '  package.preload["overseer.form"] = function()' \
        '    return {' \
        '      open = function(_, _, initial_params, on_submit)' \
        '        assert(initial_params.task_id == "20-10 : Demo task", initial_params.task_id)' \
        '        on_submit(initial_params)' \
        '      end,' \
        '    }' \
        '  end' \
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

provider=codex
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    ids)
        printf '{"version":2,"provider":"%s","ids":[]}\n' "$provider"
        exit 0
        ;;
    watch-new)
        printf '{"version":2,"provider":"%s","event":"timeout"}\n' "$provider"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

printf '{"version":2,"provider":"%s","sessions":[]}\n' "$provider"
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/fj-codex"

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
codex-new-session-does-not-wait-for-session-id-scan)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

provider=codex
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    ids)
        sleep 5
        printf 'ids-finished\n' >"${DOTFILES_TEST_TMP}/ids-finished"
        printf '{"version":2,"provider":"%s","ids":[]}\n' "$provider"
        exit 0
        ;;
    watch-new)
        printf '{"version":2,"provider":"%s","event":"timeout"}\n' "$provider"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

printf '{"version":2,"provider":"%s","sessions":[]}\n' "$provider"
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/fj-codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-new-session-does-not-wait-for-session-id-scan.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  require("serranomorante.plugins.jobs.agent_sessions").open_new("codex")' \
        '  local focused = vim.wait(1000, function()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return vim.bo[bufnr].buftype == "terminal" and vim.b[bufnr].overseer_task ~= nil' \
        '  end, 20)' \
        '  assert(focused, "new Codex task terminal waited for session id scan")' \
        '  assert(vim.fn.filereadable(vim.env.DOTFILES_TEST_TMP .. "/ids-finished") == 0, "Codex new session focus should not wait for the ids scan to finish")' \
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

provider=codex
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    ids)
        printf '{"version":2,"provider":"%s","ids":[]}\n' "$provider"
        exit 0
        ;;
    watch-new)
        printf '{"version":2,"provider":"%s","event":"timeout"}\n' "$provider"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

printf '{"version":2,"provider":"%s","sessions":[]}\n' "$provider"
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/fj-codex"

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
    cat >"${fake_bin}/cachectl" <<'SH'
#!/bin/sh
set -eu

case "$1" in
get)
    exit 1
    ;;
set)
    cat >/dev/null
    exit 0
    ;;
*)
    exit 0
    ;;
esac
SH
cat >"${fake_bin}/agent-session-store" <<'SH'
#!/bin/sh
set -eu

provider=
command_seen=
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    refresh)
        command_seen=refresh
        shift
        ;;
    sessions)
        command_seen=sessions
        shift
        ;;
    *)
        shift
        ;;
    esac
done

    case "${provider:-codex}:${command_seen:-sessions}" in
    codex:sessions)
        printf '{"version":2,"provider":"codex","sessions":[{"provider":"codex","path":"%s/session.jsonl","id":"resume-missing-cwd-session","cwd":"%s","timestamp":"2026-06-17T14:51:10Z","updated_at":"2026-06-17T15:03:39Z","title":"missing cwd session"}]}\n' "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_MISSING_CWD}"
        ;;
    codex:refresh)
        printf '{"version":2,"provider":"codex","sessions":[{"provider":"codex","path":"%s/session.jsonl","id":"resume-missing-cwd-session","cwd":"%s","timestamp":"2026-06-17T14:51:10Z","updated_at":"2026-06-17T15:03:39Z","title":"missing cwd session"}]}\n' "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_MISSING_CWD}"
        ;;
    *)
        printf '{"version":2,"provider":"%s","sessions":[]}\n' "${provider:-claude}"
        ;;
    esac
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$PWD" >"${DOTFILES_TEST_TMP}/codex-resume-pwd"
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/codex-resume-args"
printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/fj-codex"

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
        '  vim.env.CACHECTL_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/cachectl"' \
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

provider=codex
while [ "$#" -gt 0 ]; do
    case "$1" in
    --provider)
        provider=$2
        shift 2
        ;;
    ids)
        printf '{"version":2,"provider":"%s","ids":[]}\n' "$provider"
        exit 0
        ;;
    watch-new)
        printf '{"version":2,"provider":"%s","event":"timeout"}\n' "$provider"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

printf '{"version":2,"provider":"%s","sessions":[]}\n' "$provider"
SH
cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

sleep 0.2
printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
while IFS= read -r line; do
    printf '%s\n' "$line" >>"${DOTFILES_TEST_TMP}/codex-stdin"
done
SH
    chmod +x "${fake_bin}/agent-session-store" "${fake_bin}/fj-codex"

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
        '  vim.fn.setpos([['\''<]], { 0, 1, 1, 0 })' \
        '  vim.fn.setpos([['\''>]], { 0, 2, 15, 0 })' \
        '  local agent_sessions = require("serranomorante.plugins.jobs.agent_sessions")' \
        '  local prompt = agent_sessions.prompt_from_context({ visual = true })' \
        '  assert(type(prompt) == "string" and prompt:find("selected_alpha%(%)") and prompt:find("selected_beta%(%)") and prompt:find("```lua", 1, true), prompt)' \
        '  agent_sessions.open_new("codex", { visual = true })' \
        '  local started = vim.wait(5000, function()' \
        '    local bufnr = vim.api.nvim_get_current_buf()' \
        '    return vim.bo[bufnr].buftype == "terminal" and vim.b[bufnr].overseer_task ~= nil' \
        '  end, 20)' \
        '  assert(started, "new Codex task terminal was not focused")' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-new-renames-pending-tmux-session-after-session-id)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/cachectl" <<'SH'
#!/bin/sh
set -eu

case "$1" in
get)
    exit 1
    ;;
set)
    cat >/dev/null
    exit 0
    ;;
*)
    exit 0
    ;;
esac
SH
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
    ids)
        if [ -s "${DOTFILES_TEST_TMP}/tmux-calls" ]; then
            printf '{"version":2,"provider":"%s","ids":["existing-elasticsearch-session","renamed-session"]}\n' "${provider:-codex}"
        else
            printf '{"version":2,"provider":"%s","ids":["existing-elasticsearch-session"]}\n' "${provider:-codex}"
        fi
        exit 0
        ;;
    watch-new)
        known_ids=${3:-}
        case "$known_ids" in
        *renamed-session*)
            printf '{"version":2,"provider":"%s","event":"timeout"}\n' "${provider:-codex}"
            exit 0
            ;;
        *existing-elasticsearch-session*) ;;
        *)
            printf '{"version":2,"provider":"%s","event":"timeout"}\n' "${provider:-codex}"
            exit 0
            ;;
        esac
        printf '{"version":2,"provider":"%s","event":"session","session":{"provider":"%s","path":"%s/session.jsonl","id":"renamed-session","cwd":"%s","timestamp":"2026-07-07T10:34:15Z","updated_at":"2026-07-07T10:35:00Z","title":"renamed session"}}\n' "${provider:-codex}" "${provider:-codex}" "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_TMP}"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"version":2,"provider":"%s","sessions":[{"provider":"%s","path":"%s/session.jsonl","id":"renamed-session","cwd":"%s","timestamp":"%s","updated_at":"%s","title":"renamed session"}]}\n' "${provider:-codex}" "${provider:-codex}" "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_TMP}" "$now" "$now"
SH
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/tmux-calls"

case "$*" in
*" new-session "*)
    printf 'OpenAI Codex\n'
    printf 'model: fake\n'
    printf 'directory: %s\n' "$PWD"
    sleep 10
    ;;
*)
    exit 0
    ;;
esac
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/cachectl" "${fake_bin}/agent-session-store" "${fake_bin}/tmux" "${fake_bin}/fj-codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-new-renames-pending-tmux-session-after-session-id.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local session_id = "renamed-session"' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.CACHECTL_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/cachectl"' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  require("serranomorante.plugins.jobs.agent_sessions").open_new("codex")' \
        '  local matching_task' \
        '  local linked = vim.wait(5000, function()' \
        '    for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '      local metadata = task.metadata or {}' \
        '      if metadata.agent_session_id == session_id then' \
        '        matching_task = task' \
        '        return metadata.agent_tmux_session_name == "codex-" .. session_id' \
        '      end' \
        '    end' \
        '    return false' \
        '  end, 20)' \
        '  assert(linked and matching_task, "new Codex task did not link to the real session id")' \
        '  local tmux_calls = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/tmux-calls"), "\n")' \
        '  assert(tmux_calls:find("new%-session.*%-s codex%-pending%-"), tmux_calls)' \
        '  assert(tmux_calls:find("rename-session -t codex-pending-", 1, true), tmux_calls)' \
        '  assert(tmux_calls:find(" codex-" .. session_id, 1, true), tmux_calls)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
sub-agent-new-session-uses-role-aware-tmux-name)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/uuidgen" <<'SH'
#!/bin/sh
set -eu

printf '11111111-1111-4111-8111-111111111111\n'
SH
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
    ids)
        printf '{"version":2,"provider":"%s","ids":[]}\n' "${provider:-claude}"
        exit 0
        ;;
    watch-new)
        printf '{"version":2,"provider":"%s","event":"timeout"}\n' "${provider:-claude}"
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

printf '{"version":2,"provider":"%s","sessions":[]}\n' "${provider:-claude}"
SH
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/tmux-calls"

case "$*" in
*" new-session "*)
    printf 'Claude Code\n'
    printf '? for shortcuts\n'
    sleep 10
    ;;
*)
    exit 0
    ;;
esac
SH
    cat >"${fake_bin}/fj-claude" <<'SH'
#!/bin/sh
set -eu

printf 'Claude Code\n'
printf '? for shortcuts\n'
sleep 10
SH
    chmod +x "${fake_bin}/uuidgen" "${fake_bin}/agent-session-store" "${fake_bin}/tmux" "${fake_bin}/fj-claude"

    lua_file="${DOTFILES_TEST_TMP}/sub-agent-new-session-uses-role-aware-tmux-name.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local session_id = "11111111-1111-4111-8111-111111111111"' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  require("serranomorante.plugins.jobs.agent_sessions").open_new("claude", { role = "sub" })' \
        '  local matching_task' \
        '  local opened = vim.wait(5000, function()' \
        '    for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '      local metadata = task.metadata or {}' \
        '      if metadata.agent_session_id == session_id then' \
        '        matching_task = task' \
        '        return metadata.agent_role == "sub" and metadata.agent_tmux_session_name == "claude-sub-" .. session_id' \
        '      end' \
        '    end' \
        '    return false' \
        '  end, 20)' \
        '  assert(opened and matching_task, "sub-agent task did not keep role-aware tmux metadata")' \
        '  local tmux_calls = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/tmux-calls"), "\n")' \
        '  assert(tmux_calls:find("-s claude-sub-" .. session_id, 1, true), tmux_calls)' \
        '  assert(not tmux_calls:find("-s claude-" .. session_id, 1, true), tmux_calls)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-resume-ignores-cached-pending-tmux-session)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/cachectl" <<'SH'
#!/bin/sh
set -eu

case "$*" in
*" get nvim agent-tmux-session-name-v1:codex:resume-pending-cache-session"*)
    printf 'codex-pending-stale-placeholder\n'
    ;;
*)
    exit 1
    ;;
esac
SH
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
    printf '{"version":2,"provider":"codex","sessions":[{"provider":"codex","path":"%s/session.jsonl","id":"resume-pending-cache-session","cwd":"%s","timestamp":"2026-07-07T10:34:15Z","updated_at":"2026-07-07T10:35:00Z","title":"pending cache session"}]}\n' "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_TMP}"
    ;;
*)
    printf '{"version":2,"provider":"%s","sessions":[]}\n' "${provider:-claude}"
    ;;
esac
SH
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/tmux-calls"

case "$*" in
*" has-session "*"codex-pending-stale-placeholder"*)
    exit 0
    ;;
*" has-session "*)
    exit 1
    ;;
*" new-session "*)
    printf 'OpenAI Codex\n'
    printf 'model: fake\n'
    printf 'directory: %s\n' "$PWD"
    sleep 10
    ;;
*)
    exit 0
    ;;
esac
SH
    cat >"${fake_bin}/fj-codex" <<'SH'
#!/bin/sh
set -eu

printf 'OpenAI Codex\n'
printf 'model: fake\n'
printf 'directory: %s\n' "$PWD"
sleep 10
SH
    chmod +x "${fake_bin}/cachectl" "${fake_bin}/agent-session-store" "${fake_bin}/tmux" "${fake_bin}/fj-codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-resume-ignores-cached-pending-tmux-session.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local session_id = "resume-pending-cache-session"' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.CACHECTL_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/cachectl"' \
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
        '      if metadata.agent_session_id == session_id then' \
        '        matching_task = task' \
        '        if task.status == require("overseer.constants").STATUS.RUNNING then return true end' \
        '      end' \
        '    end' \
        '    return false' \
        '  end, 20)' \
        '  assert(running and matching_task, "resumed task did not start")' \
        '  assert(matching_task.metadata.agent_tmux_session_name == "codex-" .. session_id, vim.inspect(matching_task.metadata))' \
        '  local tmux_calls = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/tmux-calls"), "\n")' \
        '  assert(tmux_calls:find("-s codex-" .. session_id, 1, true), tmux_calls)' \
        '  assert(not tmux_calls:find("new-session.*codex%-pending%-stale%-placeholder"), tmux_calls)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
codex-resume-unsandboxed-uses-direct-executable)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/cachectl" <<'SH'
#!/bin/sh
set -eu

exit 1
SH
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
    printf '{"version":2,"provider":"codex","sessions":[{"provider":"codex","path":"%s/session.jsonl","id":"resume-unsandboxed-session","cwd":"%s","timestamp":"2026-07-07T10:34:15Z","updated_at":"2026-07-07T10:35:00Z","title":"unsandboxed session"}]}\n' "${DOTFILES_TEST_TMP}" "${DOTFILES_TEST_TMP}"
    ;;
*)
    printf '{"version":2,"provider":"%s","sessions":[]}\n' "${provider:-claude}"
    ;;
esac
SH
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/tmux-calls"

case "$*" in
*" new-session "*)
    printf 'OpenAI Codex\n'
    printf 'model: fake\n'
    printf 'directory: %s\n' "$PWD"
    sleep 10
    ;;
*)
    exit 0
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
    chmod +x "${fake_bin}/cachectl" "${fake_bin}/agent-session-store" "${fake_bin}/tmux" "${fake_bin}/codex"

    lua_file="${DOTFILES_TEST_TMP}/codex-resume-unsandboxed-uses-direct-executable.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local session_id = "resume-unsandboxed-session"' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  vim.env.CACHECTL_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/cachectl"' \
        '  vim.env.AGENT_SESSION_STORE_BIN = vim.env.DOTFILES_TEST_TMP .. "/bin/agent-session-store"' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  require("overseer").setup({' \
        '    component_aliases = { defaults_without_notification = { "on_exit_set_status" } },' \
        '  })' \
        '  require("serranomorante.plugins.jobs.agent_sessions").resume_by_id(session_id, { unsandboxed = true })' \
        '  local matching_task' \
        '  local running = vim.wait(5000, function()' \
        '    for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '      local metadata = task.metadata or {}' \
        '      if metadata.agent_session_id == session_id then' \
        '        matching_task = task' \
        '        if task.status == require("overseer.constants").STATUS.RUNNING then return true end' \
        '      end' \
        '    end' \
        '    return false' \
        '  end, 20)' \
        '  assert(running and matching_task, "unsandboxed resumed task did not start")' \
        '  assert(matching_task.metadata.agent_unsandboxed == true, vim.inspect(matching_task.metadata))' \
        '  assert(matching_task.metadata.agent_tmux_session_name == "codex-" .. session_id, vim.inspect(matching_task.metadata))' \
        '  local tmux_calls = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_TMP .. "/tmux-calls"), "\n")' \
        '  assert(tmux_calls:find(" codex %-a on%-request ", 1, false), tmux_calls)' \
        '  assert(not tmux_calls:find("fj%-codex"), tmux_calls)' \
        '  for _, task in ipairs(require("overseer").list_tasks({ include_ephemeral = true })) do' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
agent-tasks-dispose-kills-tmux-session)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/dispose-tmux-calls"
exit 0
SH
    chmod +x "${fake_bin}/tmux"

    lua_file="${DOTFILES_TEST_TMP}/agent-tasks-dispose-kills-tmux-session.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local calls_path = vim.env.DOTFILES_TEST_TMP .. "/dispose-tmux-calls"' \
        '  local wrapper = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_ROOT .. "/utilities/bin/agent-tasks"), "\n")' \
        '  assert(wrapper:find("dispose-kill", 1, true) ~= nil, "agent-tasks wrapper is missing dispose-kill")' \
        '  assert(wrapper:find("dispose_and_kill_tmux", 1, true) ~= nil, "agent-tasks wrapper is missing dispose_and_kill_tmux")' \
        '  local task = {' \
        '    id = 44,' \
        '    name = "codex disposable",' \
        '    metadata = {' \
        '      agent_provider = "codex",' \
        '      agent_session_id = "close-session",' \
        '      agent_tmux_session_name = "codex-close-session",' \
        '    },' \
        '    dispose = function()' \
        '      local f = assert(io.open(calls_path, "a"))' \
        '      f:write("dispose\n")' \
        '      f:close()' \
        '    end,' \
        '  }' \
        '  package.loaded["overseer"] = nil' \
        '  package.preload["overseer"] = function()' \
        '    return { list_tasks = function() return { task } end }' \
        '  end' \
        '  local agent_tasks = require("serranomorante.plugins.jobs.agent_tasks")' \
        '  agent_tasks.setup_commands()' \
        '  assert(vim.api.nvim_get_commands({}).AgentTaskDisposeAndKillTmux ~= nil, "AgentTaskDisposeAndKillTmux was not registered")' \
        '  local result = vim.json.decode(agent_tasks.dispose_and_kill_tmux("close-session"))' \
        '  assert(result.ok == true, vim.inspect(result))' \
        '  assert(result.disposed == true, vim.inspect(result))' \
        '  assert(result.tmux_killed == true, vim.inspect(result))' \
        '  assert(result.tmux_session_name == "codex-close-session", vim.inspect(result))' \
        '  local calls = table.concat(vim.fn.readfile(calls_path), "\n")' \
        '  assert(calls:match("^dispose\n%-L .+ kill%-session %-t codex%-close%-session$"), calls)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
agent-tasks-detach-from-sandbox-resumes-codex-unsandboxed)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/detach-tmux-calls"
exit 0
SH
    chmod +x "${fake_bin}/tmux"

    lua_file="${DOTFILES_TEST_TMP}/agent-tasks-detach-from-sandbox-resumes-codex-unsandboxed.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local calls_path = vim.env.DOTFILES_TEST_TMP .. "/detach-tmux-calls"' \
        '  local wrapper = table.concat(vim.fn.readfile(vim.env.DOTFILES_TEST_ROOT .. "/utilities/bin/agent-tasks"), "\n")' \
        '  assert(wrapper:find("detach-sandbox", 1, true) ~= nil, "agent-tasks wrapper is missing detach-sandbox")' \
        '  assert(wrapper:find("detach_from_sandbox", 1, true) ~= nil, "agent-tasks wrapper is missing detach_from_sandbox")' \
        '  local task = {' \
        '    id = 45,' \
        '    name = "codex sandboxed",' \
        '    metadata = {' \
        '      agent_provider = "codex",' \
        '      agent_session_id = "detach-session",' \
        '      agent_tmux_session_name = "codex-detach-session",' \
        '      agent_role = "sub",' \
        '    },' \
        '    dispose = function()' \
        '      local f = assert(io.open(calls_path, "a"))' \
        '      f:write("dispose\n")' \
        '      f:close()' \
        '    end,' \
        '  }' \
        '  local resumed' \
        '  package.loaded["overseer"] = nil' \
        '  package.preload["overseer"] = function()' \
        '    return { list_tasks = function() return { task } end }' \
        '  end' \
        '  package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_sessions"] = function()' \
        '    return {' \
        '      providers = { codex = { name = "codex", sessions_dir = "/tmp/codex" } },' \
        '      resume_by_id = function(id, opts) resumed = { id = id, opts = opts } end,' \
        '    }' \
        '  end' \
        '  local agent_tasks = require("serranomorante.plugins.jobs.agent_tasks")' \
        '  agent_tasks.setup_commands()' \
        '  assert(vim.api.nvim_get_commands({}).AgentTaskDetachFromSandbox ~= nil, "AgentTaskDetachFromSandbox was not registered")' \
        '  local result = vim.json.decode(agent_tasks.detach_from_sandbox("detach-session"))' \
        '  assert(result.ok == true, vim.inspect(result))' \
        '  assert(result.detached == true, vim.inspect(result))' \
        '  assert(result.unsandboxed == true, vim.inspect(result))' \
        '  assert(result.session_id == "detach-session", vim.inspect(result))' \
        '  assert(vim.wait(1000, function() return resumed ~= nil end, 10), "session was not resumed")' \
        '  assert(resumed.id == "detach-session", vim.inspect(resumed))' \
        '  assert(resumed.opts.role == "sub", vim.inspect(resumed))' \
        '  assert(resumed.opts.unsandboxed == true, vim.inspect(resumed))' \
        '  local calls = table.concat(vim.fn.readfile(calls_path), "\n")' \
        '  assert(calls:match("^dispose\n%-L .+ kill%-session %-t codex%-detach%-session$"), calls)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
overseer-actions-include-dispose-and-kill-tmux)
    lua_file="${DOTFILES_TEST_TMP}/overseer-actions-include-dispose-and-kill-tmux.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local captured' \
        '  local run_ref' \
        '  local detach_ref' \
        '  package.loaded["overseer"] = nil' \
        '  package.preload["overseer"] = function()' \
        '    return {' \
        '      setup = function(cfg) captured = cfg end,' \
        '      close = function() end,' \
        '      open = function() end,' \
        '      run_task = function() end,' \
        '    }' \
        '  end' \
        '  package.loaded["overseer.constants"] = nil' \
        '  package.preload["overseer.constants"] = function() return { STATUS = { RUNNING = "RUNNING", SUCCESS = "SUCCESS", FAILURE = "FAILURE" } } end' \
        '  package.loaded["serranomorante.utils"] = nil' \
        '  package.preload["serranomorante.utils"] = function()' \
        '    return {' \
        '      attach_overseer_task_output_navigation = function() end,' \
        '      close_window_on_exit_0 = function() end,' \
        '      is_kitty_cwd_servername = function() return false end,' \
        '    }' \
        '  end' \
        '  package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_sessions"] = function() return { keys = function() end } end' \
        '  package.loaded["serranomorante.plugins.jobs.agent_tasks"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_tasks"] = function()' \
        '    return {' \
        '      setup_commands = function() end,' \
        '      dispose_and_kill_tmux = function(ref) run_ref = ref end,' \
        '      detach_from_sandbox = function(ref) detach_ref = ref end,' \
        '      task_state = function() return "unknown" end,' \
        '      task_role = function() return "master" end,' \
        '    }' \
        '  end' \
        '  package.loaded["serranomorante.plugins.jobs.record_screen_actions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.record_screen_actions"] = function()' \
        '    return { is_record_screen_task = function() return false end, stop = function() end, actions = function() return {} end }' \
        '  end' \
        '  require("serranomorante.plugins.jobs.overseer").config()' \
        '  assert(captured and captured.actions and captured.actions["dispose and kill tmux"], "dispose and kill tmux action was not registered")' \
        '  local action = captured.actions["dispose and kill tmux"]' \
        '  assert(action.desc == "Dispose the task and kill its tmux session", vim.inspect(action))' \
        '  assert(action.condition({ metadata = {} }) == false, "action should be hidden without tmux metadata")' \
        '  assert(action.condition({ metadata = { agent_tmux_session_name = "codex-close-session" } }) == true, "action should be visible for tmux-backed agent tasks")' \
        '  action.run({ id = 44, metadata = { agent_tmux_session_name = "codex-close-session" } })' \
        '  assert(run_ref == "44", tostring(run_ref))' \
        '  assert(captured.actions["detach from sandbox"], "detach from sandbox action was not registered")' \
        '  local detach_action = captured.actions["detach from sandbox"]' \
        '  assert(detach_action.desc == "Dispose the sandboxed task, kill its tmux session, and resume it without Firejail", vim.inspect(detach_action))' \
        '  assert(detach_action.condition({ metadata = { agent_provider = "claude", agent_tmux_session_name = "claude-close-session" } }) == true, "detach should be visible for tmux-backed Claude tasks")' \
        '  assert(detach_action.condition({ metadata = { agent_provider = "gemini", agent_tmux_session_name = "gemini-close-session" } }) == true, "detach should be visible for tmux-backed Gemini tasks")' \
        '  assert(detach_action.condition({ metadata = { agent_provider = "codex" } }) == false, "detach should be hidden without tmux metadata")' \
        '  assert(detach_action.condition({ metadata = { agent_provider = "codex", agent_tmux_session_name = "codex-close-session" } }) == true, "detach should be visible for tmux-backed Codex tasks")' \
        '  assert(detach_action.condition({ metadata = { agent_provider = "opencode", agent_tmux_session_name = "opencode-close-session" } }) == true, "detach should be visible for tmux-backed OpenCode tasks")' \
        '  detach_action.run({ id = 45, metadata = { agent_provider = "codex", agent_tmux_session_name = "codex-close-session" } })' \
        '  assert(detach_ref == "45", tostring(detach_ref))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
agent-tasks-reconcile-opens-missing-tmux-sessions)
    fake_bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/tmux" <<'SH'
#!/bin/sh
set -eu

case "$*" in
*list-sessions*)
    printf '%s\n' \
        'codex-open-session' \
        'claude-missing-session' \
        'claude-sub-missing-sub-session' \
        'codex-pending-not-ready' \
        'claude-sub-pending-not-ready' \
        'notes-not-an-agent'
    ;;
*)
    exit 0
    ;;
esac
SH
    chmod +x "${fake_bin}/tmux"

    lua_file="${DOTFILES_TEST_TMP}/agent-tasks-reconcile-opens-missing-tmux-sessions.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.PATH = vim.env.DOTFILES_TEST_TMP .. "/bin:" .. vim.env.PATH' \
        '  local existing_task = {' \
        '    id = 11,' \
        '    name = "codex existing",' \
        '    metadata = {' \
        '      agent_provider = "codex",' \
        '      agent_session_id = "open-session",' \
        '      agent_tmux_session_name = "codex-open-session",' \
        '    },' \
        '  }' \
        '  local resumed = {}' \
        '  package.loaded["overseer"] = nil' \
        '  package.preload["overseer"] = function()' \
        '    return { list_tasks = function() return { existing_task } end }' \
        '  end' \
        '  package.loaded["serranomorante.plugins.jobs.agent_sessions"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_sessions"] = function()' \
        '    return {' \
        '      providers = {' \
        '        codex = { name = "codex", sessions_dir = "/tmp/codex" },' \
        '        claude = { name = "claude", sessions_dir = "/tmp/claude" },' \
        '      },' \
        '      resume_by_id = function(id, opts)' \
        '        table.insert(resumed, { id = id, role = opts and opts.role or "master" })' \
        '      end,' \
        '    }' \
        '  end' \
        '  vim.api.nvim_create_user_command("AgentResumeById", function(args)' \
        '    table.insert(resumed, { id = args.args, role = "fallback" })' \
        '  end, { nargs = 1, force = true })' \
        '  local agent_tasks = require("serranomorante.plugins.jobs.agent_tasks")' \
        '  agent_tasks.setup_commands()' \
        '  assert(vim.api.nvim_get_commands({}).AgentTasksReconcile ~= nil, "AgentTasksReconcile was not registered")' \
        '  local command_output = vim.fn.execute("AgentTasksReconcile")' \
        '  assert(command_output:find("Agent task reconcile: 3 tmux sessions, 1 already open, 2 reopened.", 1, true), command_output)' \
        '  assert(command_output:find("Reopened:", 1, true), command_output)' \
        '  assert(command_output:find("claude master missin", 1, true), command_output)' \
        '  assert(command_output:find("claude sub missin", 1, true), command_output)' \
        '  assert(not command_output:find("^%s*{"), command_output)' \
        '  assert(vim.wait(1000, function() return #resumed == 2 end, 10), "missing sessions were not resumed")' \
        '  local resumed_by_id = {}' \
        '  for _, item in ipairs(resumed) do resumed_by_id[item.id] = item.role end' \
        '  assert(resumed_by_id["missing-session"] == "master", vim.inspect(resumed))' \
        '  assert(resumed_by_id["missing-sub-session"] == "sub", vim.inspect(resumed))' \
        '  assert(existing_task.metadata.agent_role == nil, vim.inspect(existing_task.metadata))' \
        '  resumed = {}' \
        '  local result = vim.json.decode(agent_tasks.reconcile())' \
        '  assert(result.ok == true, vim.inspect(result))' \
        '  assert(result.tmux_sessions == 3, vim.inspect(result))' \
        '  assert(result.existing_count == 1, vim.inspect(result))' \
        '  assert(result.opened_count == 2, vim.inspect(result))' \
        '  assert(result.opened[1].provider == "claude", vim.inspect(result.opened))' \
        '  assert(result.opened[1].session_id == "missing-session", vim.inspect(result.opened))' \
        '  assert(result.opened[1].role == "master", vim.inspect(result.opened))' \
        '  assert(result.opened[2].session_id == "missing-sub-session", vim.inspect(result.opened))' \
        '  assert(result.opened[2].role == "sub", vim.inspect(result.opened))' \
        '  assert(vim.wait(1000, function() return #resumed == 2 end, 10), "missing sessions were not resumed")' \
        '  resumed_by_id = {}' \
        '  for _, item in ipairs(resumed) do resumed_by_id[item.id] = item.role end' \
        '  assert(resumed_by_id["missing-session"] == "master", vim.inspect(resumed))' \
        '  assert(resumed_by_id["missing-sub-session"] == "sub", vim.inspect(resumed))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
refresh-terminal-window-resizes-agent-tmux)
    lua_file="${DOTFILES_TEST_TMP}/refresh-terminal-window-resizes-agent-tmux.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local resize_calls = 0' \
        '  package.loaded["serranomorante.plugins.jobs.agent_tasks"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_tasks"] = function()' \
        '    return { resize_tmux_sessions = function() resize_calls = resize_calls + 1; return "{}" end }' \
        '  end' \
        '  local utils = require("serranomorante.utils")' \
        '  utils.refresh_terminal_window()' \
        '  assert(resize_calls == 1, "refresh_terminal_window should resize agent tmux sessions")' \
        '  package.loaded["serranomorante.plugins.jobs.agent_tasks"] = nil' \
        '  package.preload["serranomorante.plugins.jobs.agent_tasks"] = function()' \
        '    return { resize_tmux_sessions = function() error("resize failed") end }' \
        '  end' \
        '  utils.refresh_terminal_window()' \
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
