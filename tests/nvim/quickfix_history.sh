#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless quickfix local-state
# dotfiles-test-firejail: disabled
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: nvim-quickfix-history-restores-stack

# Purpose: Check CWD-scoped quickfix stack persistence.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local cwd=$1
    local lua_file=$2
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-qf.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-qf.XXXXXX")
    mkdir -p "$runtime_dir"
    (
        cd "$cwd"
        export XDG_RUNTIME_DIR="$runtime_dir"
        "$nvim_bin" \
            --headless \
            --listen "${runtime_dir}/kitty-cwd-test.nvim.sock" \
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
nvim-quickfix-history-restores-stack)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "$project"
    printf 'alpha\n' >"${project}/alpha.txt"
    printf 'beta\n' >"${project}/beta.txt"

    save_lua="${DOTFILES_TEST_TMP}/quickfix-save.lua"
    restore_lua="${DOTFILES_TEST_TMP}/quickfix-restore.lua"

    write_lua "$save_lua" \
        'local function main()' \
        '  require("serranomorante")' \
        '  vim.cmd.runtime("after/plugin/quickfix.lua")' \
        '  vim.cmd.edit("alpha.txt")' \
        '  local alpha_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.fn.setqflist({}, " ", { title = "first", idx = 1, context = { name = "one" }, items = { { bufnr = alpha_bufnr, lnum = 1, col = 1, text = "alpha" } } })' \
        '  vim.fn.setqflist({}, " ", { title = "second", idx = 1, context = { name = "two" }, items = { { filename = vim.fn.getcwd() .. "/beta.txt", lnum = 1, col = 1, text = "beta" } } })' \
        '  vim.cmd("silent 1chistory")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'

    write_lua "$restore_lua" \
        'local function main()' \
        '  require("serranomorante")' \
        '  vim.cmd.runtime("after/plugin/quickfix.lua")' \
        '  local total = vim.fn.getqflist({ nr = "$" }).nr' \
        '  assert(total == 2, "expected two restored quickfix lists, got " .. total)' \
        '  local current = vim.fn.getqflist({ nr = 0, title = 0 })' \
        '  assert(current.nr == 1 and current.title == "first", vim.inspect(current))' \
        '  local first = vim.fn.getqflist({ nr = 1, title = 0, items = 0, context = 0 })' \
        '  local second = vim.fn.getqflist({ nr = 2, title = 0, items = 0, context = 0 })' \
        '  assert(first.title == "first" and first.context.name == "one", vim.inspect(first))' \
        '  assert(second.title == "second" and second.context.name == "two", vim.inspect(second))' \
        '  assert(first.items[1].text == "alpha" and vim.api.nvim_buf_get_name(first.items[1].bufnr):match("alpha%.txt$"), vim.inspect(first.items[1]))' \
        '  assert(second.items[1].text == "beta" and vim.api.nvim_buf_get_name(second.items[1].bufnr):match("beta%.txt$"), vim.inspect(second.items[1]))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'

    run_nvim_lua_file "$project" "$save_lua"
    run_nvim_lua_file "$project" "$restore_lua"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
