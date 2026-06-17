#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless overseer markdown shell-fence terminal
# dotfiles-test-firejail: disabled
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: markdown-shell-fence-keymap-works-from-file-scratch-nofile-terminal-float

# Purpose: Guard the Markdown <leader>mr shell-fence runner across buffer kinds and its Overseer task contract.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-shell-fence.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-shell-fence.XXXXXX")
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
markdown-shell-fence-keymap-works-from-file-scratch-nofile-terminal-float)
    lua_file="${DOTFILES_TEST_TMP}/markdown-shell-fence-keymap-works-from-file-scratch-nofile-terminal-float.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.opt.packpath:prepend("/home/aaaa/.local/share/nvim/site")' \
        '  vim.cmd.packloadall()' \
        '  local overseer = require("overseer")' \
        '  overseer.setup({' \
        '    output = { use_terminal = true, preserve_output = true },' \
        '  })' \
        '  vim.g.mapleader = " "' \
        '  require("serranomorante.remap")' \
        '  assert(vim.fn.maparg("<leader>mr", "x") ~= "", "visual <leader>mr keymap should be registered")' \
        '  local utils_path = vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/utils.lua"' \
        '  local utils_text = table.concat(vim.fn.readfile(utils_path), "\n")' \
        '  local run_shell_fence = utils_text:match("function M%.run_shell_fence%([^)]*%)%s*(.-)%s*return M")' \
        '  assert(run_shell_fence, "could not find run_shell_fence implementation")' \
        '  assert(not run_shell_fence:find("defer_fn", 1, true), "run_shell_fence must not rely on defer_fn timing")' \
        '  assert(not run_shell_fence:find("schedule_open_overseer_task_output", 1, true), "run_shell_fence must not use retry-based output scheduling")' \
        '  assert(run_shell_fence:find("open_started_overseer_task_output", 1, true), "run_shell_fence should open the started task output directly")' \
        '  assert(run_shell_fence:find("shell_fence_cwd", 1, true), "run_shell_fence should use a cwd resolver that works for non-file buffers")' \
        '  assert(run_shell_fence:find("prepare_shell_fence_task_start_window", 1, true), "run_shell_fence should choose a regular output window for terminal/float sources")' \
        '  assert(not run_shell_fence:find("alternate_bufnr", 1, true), "run_shell_fence should rely on normal buffer history instead of synthetic alternates")' \
        '  local function set_fence_lines(command)' \
        '    local body = type(command) == "table" and command or { command }' \
        '    local lines = { "```sh" }' \
        '    vim.list_extend(lines, body)' \
        '    table.insert(lines, "```")' \
        '    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)' \
        '    vim.api.nvim_win_set_cursor(0, { 2, 0 })' \
        '  end' \
        '  local function cursor_to_line_containing(text)' \
        '    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do' \
        '      if line:find(text, 1, true) then' \
        '        vim.api.nvim_win_set_cursor(0, { lnum, 0 })' \
        '        return' \
        '      end' \
        '    end' \
        '    error("could not find line containing " .. text)' \
        '  end' \
        '  local function run_current_fence(expected)' \
        '    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(" mr", true, false, true), "x", false)' \
        '    local task' \
        '    assert(vim.wait(5000, function()' \
        '      for _, candidate in ipairs(overseer.list_tasks({ include_ephemeral = true })) do' \
        '        if candidate.name:find("^shell fence:") then' \
        '          local bufnr = candidate:get_bufnr()' \
        '          if bufnr and vim.api.nvim_buf_is_valid(bufnr) then' \
        '            local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")' \
        '            if text:find(expected, 1, true) then' \
        '              task = candidate' \
        '              return true' \
        '            end' \
        '          end' \
        '        end' \
        '      end' \
        '      return false' \
        '    end, 20), "shell fence output was not opened for " .. expected)' \
        '    assert(task:has_component("on_complete_dispose"), "shell fence tasks should auto-dispose after completion")' \
        '    local bufnr = task:get_bufnr()' \
        '    local task_bufname = vim.api.nvim_buf_get_name(bufnr)' \
        '    assert(task_bufname == ("task://shell-fenced %s"):format(task.id), task_bufname)' \
        '    assert(not task_bufname:find("overseer-", 1, true), task_bufname)' \
        '    assert(vim.bo[bufnr].filetype == "OverseerOutput", vim.bo[bufnr].filetype)' \
        '    assert(vim.bo[bufnr].buflisted, "shell fence output should be listed")' \
        '    assert(vim.fn.bufwinid(bufnr) ~= -1, "shell fence output should be visible")' \
        '    assert(vim.api.nvim_get_mode().mode ~= "t", "shell fence output should not leave Neovim in terminal insert mode")' \
        '    pcall(function() task:dispose(true) end)' \
        '  end' \
        '  local function run_visual_shell_selection(start_lnum, end_lnum, expected)' \
        '    vim.api.nvim_win_set_cursor(0, { start_lnum, 0 })' \
        '    vim.api.nvim_feedkeys(("V%dG"):format(end_lnum), "x", false)' \
        '    assert(vim.api.nvim_get_mode().mode == "V", "visual selection was not active")' \
        '    run_current_fence(expected)' \
        '  end' \
        '  local project = vim.env.DOTFILES_TEST_TMP .. "/shell-fence-project"' \
        '  vim.fn.mkdir(project, "p")' \
        '  local note_path = project .. "/note.md"' \
        '  vim.fn.writefile({ "# Note", "", "```sh", "printf file-fence-ok", "```" }, note_path)' \
        '  vim.cmd.edit(note_path)' \
        '  vim.api.nvim_win_set_cursor(0, { 4, 0 })' \
        '  run_current_fence("file-fence-ok")' \
        '  vim.cmd("enew!")' \
        '  set_fence_lines("printf scratch-fence-ok")' \
        '  run_current_fence("scratch-fence-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, {' \
        '    "printf visual-selection-first-ok",' \
        '    "printf visual-selection-second-ok",' \
        '  })' \
        '  run_visual_shell_selection(1, 2, "visual-selection-second-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.bo.buftype = "nofile"' \
        '  vim.api.nvim_buf_set_name(0, "nofile://shell-fence-test")' \
        '  set_fence_lines("printf nofile-fence-ok")' \
        '  run_current_fence("nofile-fence-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, {' \
        '    "  ```sh",' \
        '    "  cat <<'\''EOF'\''",' \
        '    "  indented-heredoc-ok",' \
        '    "  EOF",' \
        '    "  ```",' \
        '  })' \
        '  vim.api.nvim_win_set_cursor(0, { 3, 0 })' \
        '  run_current_fence("indented-heredoc-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, {' \
        '    "```sh",' \
        '    "    cat <<'\''PY'\''",' \
        '    "    nested-body-heredoc-ok",' \
        '    "    PY",' \
        '    "```",' \
        '  })' \
        '  vim.api.nvim_win_set_cursor(0, { 3, 0 })' \
        '  run_current_fence("nested-body-heredoc-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, {' \
        '    "• ```sh",' \
        '    "printf transcript-prefix-fence-ok",' \
        '    "```",' \
        '  })' \
        '  vim.api.nvim_win_set_cursor(0, { 2, 0 })' \
        '  run_current_fence("transcript-prefix-fence-ok")' \
        '  vim.cmd("enew!")' \
        '  vim.api.nvim_buf_set_lines(0, 0, -1, false, {' \
        '    "│ ```sh",' \
        '    "printf transcript-blank-cursor-ok",' \
        '    "",' \
        '    "│ ```",' \
        '  })' \
        '  vim.api.nvim_win_set_cursor(0, { 3, 0 })' \
        '  run_current_fence("transcript-blank-cursor-ok")' \
        '  local float_bufnr = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_buf_set_option(float_bufnr, "buftype", "nofile")' \
        '  local float_winid = vim.api.nvim_open_win(float_bufnr, true, { relative = "editor", row = 1, col = 1, width = 40, height = 5, style = "minimal" })' \
        '  set_fence_lines("printf float-fence-ok")' \
        '  run_current_fence("float-fence-ok")' \
        '  pcall(vim.api.nvim_win_close, float_winid, true)' \
        '  vim.cmd("enew!")' \
        '  local terminal_bufnr = vim.api.nvim_get_current_buf()' \
        '  local job = vim.fn.termopen({ "sh", "-c", "printf \"\\\\140\\\\140\\\\140sh\\\\nprintf terminal-fence-ok\\\\n\\\\140\\\\140\\\\140\\\\n\"; sleep 5" })' \
        '  assert(job > 0, "termopen failed")' \
        '  assert(vim.wait(1000, function()' \
        '    return table.concat(vim.api.nvim_buf_get_lines(terminal_bufnr, 0, -1, false), "\n"):find("terminal%-fence%-ok") ~= nil' \
        '  end, 20), "terminal fence text did not render")' \
        '  vim.cmd.stopinsert()' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "x", false)' \
        '  cursor_to_line_containing("terminal-fence-ok")' \
        '  assert(vim.bo[vim.api.nvim_get_current_buf()].buftype == "terminal", "terminal case should execute from a terminal buffer")' \
        '  run_current_fence("terminal-fence-ok")' \
        '  pcall(vim.fn.jobstop, job)' \
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
