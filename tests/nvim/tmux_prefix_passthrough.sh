#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless terminal tmux passthrough
# dotfiles-test-firejail: disabled
# dotfiles-test-case: tmux-prefix-passthrough-sends-chord
# dotfiles-test-case: tmux-prefix-passthrough-detects-tmux-under-shell
# dotfiles-test-case: tmux-prefix-passthrough-skips-non-tmux-terminals
# dotfiles-test-case: tmux-prefix-passthrough-registers-configurable-chords

# Purpose: Guard the tmux prefix passthrough added for terminal buffers: a
# Normal-mode chord (C-s + key, configured in constants.TMUX_PREFIX_PASSTHROUGHS)
# must reach a tmux running inside the terminal, only when tmux is actually
# running there, and the chord must be registered from the config list.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

require_tool() {
    local tool=$1
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'missing required tool: %s\n' "$tool" >&2
        exit 77
    fi
}

run_nvim_lua_file() {
    local lua_file=$1
    if [[ ! -x "$nvim_bin" ]]; then
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    fi
    TERM=xterm-256color "$nvim_bin" \
        --headless \
        --noplugin \
        -u NONE \
        -i NONE \
        -c "set rtp^=${rtp}" \
        -S "$lua_file"
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

write_tmux_passthrough_config() {
    local cfg=$1
    local marker=$2
    cat >"$cfg" <<EOF
set -g prefix C-s
set -g default-terminal "xterm-256color"
bind-key g run-shell 'touch "$marker"'
EOF
}

case "${DOTFILES_TEST_CASE:-}" in
tmux-prefix-passthrough-sends-chord)
    require_tool tmux
    marker="${DOTFILES_TEST_TMP}/tmux-prefix-picked"
    cfg="${DOTFILES_TEST_TMP}/tmux-passthrough.conf"
    rm -f "$marker"
    write_tmux_passthrough_config "$cfg" "$marker"

    lua_file="${DOTFILES_TEST_TMP}/tmux-prefix-sends-chord.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.TMUX_TMPDIR = vim.env.DOTFILES_TEST_TMP .. "/tmux-sock"' \
        '  local cfg = vim.env.DOTFILES_TEST_TMP .. "/tmux-passthrough.conf"' \
        '  local marker = vim.env.DOTFILES_TEST_TMP .. "/tmux-prefix-picked"' \
        '  local utils = require("serranomorante.utils")' \
        '  local buf = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(buf)' \
        '  local job = vim.fn.termopen({ "tmux", "-f", cfg, "new-session", "-s", "passthrough", "-x", "80", "-y", "24" })' \
        '  assert(job > 0, "termopen failed for tmux")' \
        '  local job_id = utils.terminal_job_id(buf)' \
        '  assert(job_id, "no terminal job id")' \
        '  local ready = vim.wait(8000, function()' \
        '    vim.fn.system({ "tmux", "ls" })' \
        '    return vim.v.shell_error == 0' \
        '  end, 30)' \
        '  assert(ready, "tmux server did not become ready")' \
        '  vim.wait(400, function() return false end, 20)' \
        '  assert(utils.send_tmux_prefix_to_terminal(buf, "g"), "prefix chord was not forwarded")' \
        '  local picked = vim.wait(5000, function() return vim.fn.filereadable(marker) == 1 end, 20)' \
        '  assert(picked, "tmux marks-picker binding did not run")' \
        '  vim.fn.system({ "tmux", "kill-server" })' \
        '  pcall(vim.fn.jobstop, job)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
tmux-prefix-passthrough-detects-tmux-under-shell)
    require_tool tmux
    marker="${DOTFILES_TEST_TMP}/tmux-prefix-picked"
    cfg="${DOTFILES_TEST_TMP}/tmux-passthrough.conf"
    rm -f "$marker"
    write_tmux_passthrough_config "$cfg" "$marker"

    lua_file="${DOTFILES_TEST_TMP}/tmux-prefix-under-shell.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.env.TMUX_TMPDIR = vim.env.DOTFILES_TEST_TMP .. "/tmux-sock-shell"' \
        '  local cfg = vim.env.DOTFILES_TEST_TMP .. "/tmux-passthrough.conf"' \
        '  local marker = vim.env.DOTFILES_TEST_TMP .. "/tmux-prefix-picked"' \
        '  local utils = require("serranomorante.utils")' \
        '  local buf = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(buf)' \
        '  local job = vim.fn.termopen({ "sh", "-c", "tmux -f '\''" .. cfg .. "'\'' new-session -s passthrough -x 80 -y 24" })' \
        '  assert(job > 0, "termopen failed for shell")' \
        '  local job_id = utils.terminal_job_id(buf)' \
        '  assert(job_id, "no terminal job id")' \
        '  local pid = vim.fn.jobpid(job_id)' \
        '  assert(pid > 0, "no job pid")' \
        '  local detected = vim.wait(8000, function() return utils.pid_runs_tmux(pid) end, 30)' \
        '  assert(detected, "tmux under the shell job was not detected")' \
        '  local ready = vim.wait(8000, function()' \
        '    vim.fn.system({ "tmux", "ls" })' \
        '    return vim.v.shell_error == 0' \
        '  end, 30)' \
        '  assert(ready, "tmux server did not become ready")' \
        '  vim.wait(400, function() return false end, 20)' \
        '  assert(utils.send_tmux_prefix_to_terminal(buf, "g"), "prefix chord was not forwarded through the shell")' \
        '  local picked = vim.wait(5000, function() return vim.fn.filereadable(marker) == 1 end, 20)' \
        '  assert(picked, "tmux marks-picker binding did not run")' \
        '  vim.fn.system({ "tmux", "kill-server" })' \
        '  pcall(vim.fn.jobstop, job)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
tmux-prefix-passthrough-skips-non-tmux-terminals)
    lua_file="${DOTFILES_TEST_TMP}/tmux-prefix-skips.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local plain_buf = vim.api.nvim_create_buf(false, true)' \
        '  vim.api.nvim_set_current_buf(plain_buf)' \
        '  local plain_job = vim.fn.termopen({ "sh", "-c", "sleep 30" })' \
        '  assert(plain_job > 0, "termopen failed for plain shell")' \
        '  local plain_pid = vim.fn.jobpid(plain_job)' \
        '  assert(not utils.pid_runs_tmux(plain_pid), "plain shell must not look like tmux")' \
        '  assert(not utils.send_tmux_prefix_to_terminal(plain_buf, "g"), "plain shell must not receive the prefix chord")' \
        '  local code_buf = vim.api.nvim_create_buf(false, false)' \
        '  vim.api.nvim_set_current_buf(code_buf)' \
        '  assert(not utils.send_tmux_prefix_to_terminal(code_buf, "g"), "non-terminal buffer must be rejected")' \
        '  vim.fn.jobstop(plain_job)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$lua_file"
    ;;
tmux-prefix-passthrough-registers-configurable-chords)
    lua_file="${DOTFILES_TEST_TMP}/tmux-prefix-registers.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.autocmds")' \
        '  local utils = require("serranomorante.utils")' \
        '  local constants = require("serranomorante.constants")' \
        '  local passthroughs = constants.TMUX_PREFIX_PASSTHROUGHS' \
        '  assert(#passthroughs >= 1, "expected at least one configured passthrough")' \
        '  for _, passthrough in ipairs(passthroughs) do' \
        '    assert(passthrough.lhs ~= nil and passthrough.lhs ~= "", "passthrough needs an lhs")' \
        '    assert(passthrough.keys ~= nil and passthrough.keys ~= "", "passthrough needs tmux keys")' \
        '    local buf = vim.api.nvim_create_buf(false, true)' \
        '    vim.api.nvim_set_current_buf(buf)' \
        '    local job = vim.fn.termopen({ "sh", "-c", "sleep 30" })' \
        '    assert(job > 0, "termopen failed")' \
        '    vim.api.nvim_exec_autocmds("TermOpen", { buffer = buf })' \
        '    local found' \
        '    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do' \
        '      if map.lhs:lower() == passthrough.lhs:lower() then found = map end' \
        '    end' \
        '    assert(found, "missing terminal Normal-mode map " .. passthrough.lhs)' \
        '    assert(type(found.callback) == "function", passthrough.lhs .. " should run a callback")' \
        '    assert(found.desc == passthrough.desc, "unexpected desc for " .. passthrough.lhs)' \
        '    assert(pcall(found.callback), passthrough.lhs .. " callback must not error on a plain shell")' \
        '    assert(vim.fn.bufexists(buf) == 1 and vim.bo[buf].buftype == "terminal", "terminal buffer should exist")' \
        '    vim.fn.jobstop(job)' \
        '  end' \
        '  local plain_buf = vim.api.nvim_create_buf(false, false)' \
        '  for _, passthrough in ipairs(passthroughs) do' \
        '    for _, map in ipairs(vim.api.nvim_buf_get_keymap(plain_buf, "n")) do' \
        '      assert(map.lhs:lower() ~= passthrough.lhs:lower(), "passthrough chord must stay terminal-buffer local")' \
        '    end' \
        '  end' \
        '  assert(utils.send_tmux_prefix_to_terminal(plain_buf, "g") == false, "non-terminal buffer must be rejected")' \
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
