#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless tabline agent-session
# dotfiles-test-firejail: disabled
# dotfiles-test-case: agent-task-sub-tabline-highlight

# Purpose: Guard custom tabline highlighting for sub-agent Overseer task tabs.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local lua_file=$1
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim-agent-tabline.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim-agent-tabline.XXXXXX")
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
agent-task-sub-tabline-highlight)
    lua_file="${DOTFILES_TEST_TMP}/agent-task-sub-tabline-highlight.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.cmd.colorscheme("default")' \
        '  local tabline = require("serranomorante.tabline")' \
        '  tabline.setup()' \
        '  assert(vim.o.tabline == "%!v:lua.require('\''serranomorante.tabline'\'').render()", vim.o.tabline)' \
        '  local master_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(master_bufnr, "task://MASTER-codex")' \
        '  vim.cmd.tabnew()' \
        '  local sub_bufnr = vim.api.nvim_get_current_buf()' \
        '  vim.api.nvim_buf_set_name(sub_bufnr, "task://SUB-codex")' \
        '  local rendered = tabline.render()' \
        '  assert(rendered:find("%#TabLine#%1T 1:MASTER-codex ", 1, true), rendered)' \
        '  assert(rendered:find("%#CustomAgentSubTabLineSel#%2T 2:SUB-codex ", 1, true), rendered)' \
        '  vim.cmd.tabprevious()' \
        '  rendered = tabline.render()' \
        '  assert(rendered:find("%#TabLineSel#%1T 1:MASTER-codex ", 1, true), rendered)' \
        '  assert(rendered:find("%#CustomAgentSubTabLine#%2T 2:SUB-codex ", 1, true), rendered)' \
        '  assert(vim.api.nvim_get_hl(0, { name = "TabLineSel" }).bg ~= nil, "master TabLineSel highlight should remain defined")' \
        '  assert(vim.api.nvim_get_hl(0, { name = "CustomAgentSubTabLineSel" }).bg ~= nil, "sub selected highlight should be defined")' \
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
