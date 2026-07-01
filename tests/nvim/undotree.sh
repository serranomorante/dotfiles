#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless undotree floating-window
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: undotree-float-window-moves-buffer-to-new-tab
# dotfiles-test-case: undotree-regular-window-keeps-current-tab

# Purpose: Verify undotree moves floating scratch buffers into a normal tab before opening.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless --noplugin -u NONE -i NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

case "${DOTFILES_TEST_CASE:-}" in
undotree-float-window-moves-buffer-to-new-tab)
    run_nvim_lua '
      vim.api.nvim_create_user_command("Undotree", function() vim.g.undotree_called = true end, {})
      local helper = require("serranomorante.plugins.undotree")
      local float_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(float_bufnr, 0, -1, false, { "scratch" })
      local float_winid = vim.api.nvim_open_win(float_bufnr, true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 24,
        height = 5,
        style = "minimal",
      })
      helper.open()
      assert(vim.g.undotree_called == true)
      assert(not vim.api.nvim_win_is_valid(float_winid))
      assert(vim.api.nvim_win_get_config(0).relative == "")
      assert(vim.api.nvim_get_current_buf() == float_bufnr)
      assert(vim.fn.tabpagenr("$") == 2)
      vim.cmd.qa({ bang = true })
    '
    ;;
undotree-regular-window-keeps-current-tab)
    run_nvim_lua '
      vim.api.nvim_create_user_command("Undotree", function() vim.g.undotree_called = true end, {})
      local helper = require("serranomorante.plugins.undotree")
      local bufnr = vim.api.nvim_get_current_buf()
      local tab_count = vim.fn.tabpagenr("$")
      helper.open()
      assert(vim.g.undotree_called == true)
      assert(vim.api.nvim_get_current_buf() == bufnr)
      assert(vim.fn.tabpagenr("$") == tab_count)
      vim.cmd.qa({ bang = true })
    '
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
