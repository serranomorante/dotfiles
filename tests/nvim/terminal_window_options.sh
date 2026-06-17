#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless terminal window-options
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: terminal-window-options-hide-editor-columns
# dotfiles-test-case: terminal-window-options-restore-regular-buffer-options
# dotfiles-test-case: terminal-window-options-leave-regular-buffer-untouched
# dotfiles-test-case: terminal-window-options-tabedit-from-terminal-restores-regular-options

# Purpose: Guard terminal-only window column options and restoration for regular buffers.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless --noplugin -u NONE -i NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

load_terminal_autocmds='dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/lua/serranomorante/autocmds.lua")'

case "${DOTFILES_TEST_CASE:-}" in
terminal-window-options-hide-editor-columns)
    run_nvim_lua "${load_terminal_autocmds}; local termbuf = vim.api.nvim_create_buf(true, true); vim.api.nvim_win_set_buf(0, termbuf); vim.fn.termopen({ 'sh', '-c', 'printf ok' }); assert(vim.bo[termbuf].buftype == 'terminal'); assert(vim.wo.number == false); assert(vim.wo.relativenumber == false); assert(vim.wo.signcolumn == 'no'); assert(vim.wo.foldcolumn == '0'); assert(vim.wo.foldenable == false); vim.cmd.qa({ bang = true })"
    ;;
terminal-window-options-restore-regular-buffer-options)
    run_nvim_lua "${load_terminal_autocmds}; local filebuf = vim.api.nvim_create_buf(true, false); vim.api.nvim_win_set_buf(0, filebuf); vim.wo.number = true; vim.wo.relativenumber = true; vim.wo.signcolumn = 'yes'; vim.wo.foldcolumn = '2'; vim.wo.foldenable = true; local termbuf = vim.api.nvim_create_buf(true, true); vim.api.nvim_win_set_buf(0, termbuf); vim.fn.termopen({ 'sh', '-c', 'printf ok' }); assert(vim.bo[termbuf].buftype == 'terminal'); assert(vim.wo.number == false); assert(vim.wo.relativenumber == false); assert(vim.wo.signcolumn == 'no'); assert(vim.wo.foldcolumn == '0'); assert(vim.wo.foldenable == false); vim.api.nvim_win_set_buf(0, filebuf); assert(vim.wo.number == true); assert(vim.wo.relativenumber == true); assert(vim.wo.signcolumn == 'yes'); assert(vim.wo.foldcolumn == '2'); assert(vim.wo.foldenable == true); vim.cmd.qa({ bang = true })"
    ;;
terminal-window-options-leave-regular-buffer-untouched)
    run_nvim_lua "${load_terminal_autocmds}; vim.wo.number = true; vim.wo.relativenumber = false; vim.wo.signcolumn = 'auto:2-4'; vim.wo.foldcolumn = '1'; vim.wo.foldenable = true; local filebuf = vim.api.nvim_create_buf(true, false); vim.api.nvim_win_set_buf(0, filebuf); assert(vim.wo.number == true); assert(vim.wo.relativenumber == false); assert(vim.wo.signcolumn == 'auto:2-4'); assert(vim.wo.foldcolumn == '1'); assert(vim.wo.foldenable == true); vim.cmd.qa({ bang = true })"
    ;;
terminal-window-options-tabedit-from-terminal-restores-regular-options)
    run_nvim_lua "${load_terminal_autocmds}; vim.wo.number = true; vim.wo.relativenumber = true; vim.wo.signcolumn = 'yes'; vim.wo.foldcolumn = '2'; vim.wo.foldenable = true; local termbuf = vim.api.nvim_create_buf(true, true); vim.api.nvim_win_set_buf(0, termbuf); vim.fn.termopen({ 'sh', '-c', 'printf ok' }); assert(vim.bo[termbuf].buftype == 'terminal'); assert(vim.wo.number == false); assert(vim.wo.signcolumn == 'no'); assert(vim.wo.foldcolumn == '0'); vim.cmd.tabedit(); assert(vim.bo.buftype ~= 'terminal'); assert(vim.wo.number == true); assert(vim.wo.relativenumber == true); assert(vim.wo.signcolumn == 'yes'); assert(vim.wo.foldcolumn == '2'); assert(vim.wo.foldenable == true); vim.cmd.qa({ bang = true })"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
