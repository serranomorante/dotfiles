#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless scratch floating-window
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: persistent-scratch-padding-uses-visual-margins
# dotfiles-test-case: persistent-scratch-undo-history-survives-reopen

# Purpose: Verify the persistent scratch float leaves visual breathing room without changing buffer contents and keeps undo history durable across reopen.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless --noplugin -u NONE -i NONE -c "set rtp^=${rtp}" -c "lua local ok, err = xpcall(function() ${lua} end, debug.traceback); if not ok then vim.api.nvim_err_writeln(err); vim.cmd.cquit({ args = '1' }) end" -c 'qa!'
}

case "${DOTFILES_TEST_CASE:-}" in
persistent-scratch-padding-uses-visual-margins)
    project=$(mktemp -d "${DOTFILES_TEST_TMP}/persistent-scratch-project.XXXXXX")
    state_home="${DOTFILES_TEST_TMP}/xdg-state"
    cache_home="${DOTFILES_TEST_TMP}/xdg-cache"
    mkdir -p "$state_home" "$cache_home"
    DOTFILES_TEST_PROJECT="$project" XDG_STATE_HOME="$state_home" XDG_CACHE_HOME="$cache_home" run_nvim_lua '
      local utils = require("serranomorante.utils")
      vim.fn.chdir(vim.env.DOTFILES_TEST_PROJECT)
      dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/plugin/persistent_scratch.lua")
      local scratch = require("serranomorante.persistent_scratch")
      scratch.toggle()
      local winid = vim.api.nvim_get_current_win()
      local bufnr = vim.api.nvim_win_get_buf(winid)
      assert(vim.bo[bufnr].buftype == "", "scratch buffer should be file-backed")
      assert(vim.bo[bufnr].filetype == "markdown")
      assert(vim.bo[bufnr].undofile == true)
      assert(vim.wo.signcolumn == "yes:1")
      assert(vim.wo.foldcolumn == "1")
      local contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert(#contents == 1 and contents[1] == "", "scratch buffer should start empty")
      assert(scratch.append_lines({ "hello" }) == true)
      local key = utils.local_state_cwd_key(vim.fn.getcwd())
      local scratch_path = vim.fn.stdpath("state") .. "/persistent-scratch/" .. key .. ".md"
      assert(vim.api.nvim_buf_get_name(bufnr) == scratch_path, vim.api.nvim_buf_get_name(bufnr))
      local saved = vim.fn.readfile(scratch_path)
      assert(#saved == 1 and saved[1] == "hello", "saved scratch should omit padding")
      vim.cmd.qa({ bang = true })
    '
    ;;
persistent-scratch-undo-history-survives-reopen)
    project=$(mktemp -d "${DOTFILES_TEST_TMP}/persistent-scratch-project.XXXXXX")
    state_home="${DOTFILES_TEST_TMP}/xdg-state"
    cache_home="${DOTFILES_TEST_TMP}/xdg-cache"
    undo_dir="${DOTFILES_TEST_TMP}/undo"
    mkdir -p "$state_home" "$cache_home" "$undo_dir"

    DOTFILES_TEST_PROJECT="$project" XDG_STATE_HOME="$state_home" XDG_CACHE_HOME="$cache_home" DOTFILES_TEST_UNDO_DIR="$undo_dir" run_nvim_lua '
      local utils = require("serranomorante.utils")
      vim.o.undofile = false
      vim.o.undodir = vim.env.DOTFILES_TEST_UNDO_DIR
      vim.fn.chdir(vim.env.DOTFILES_TEST_PROJECT)
      dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/plugin/persistent_scratch.lua")
      local scratch = require("serranomorante.persistent_scratch")
      scratch.toggle()
      local bufnr = vim.api.nvim_get_current_buf()
      assert(vim.bo[bufnr].undofile == true, "scratch buffer should keep undo persistence enabled")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "alpha" })
      vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "beta" })
      vim.cmd.write()
      local key = utils.local_state_cwd_key(vim.fn.getcwd())
      local scratch_path = vim.fn.stdpath("state") .. "/persistent-scratch/" .. key .. ".md"
      assert(vim.fn.filereadable(scratch_path) == 1, "scratch file should be written to disk")
      vim.cmd.qa({ bang = true })
    '

    DOTFILES_TEST_PROJECT="$project" XDG_STATE_HOME="$state_home" XDG_CACHE_HOME="$cache_home" DOTFILES_TEST_UNDO_DIR="$undo_dir" run_nvim_lua '
      local utils = require("serranomorante.utils")
      vim.o.undofile = false
      vim.o.undodir = vim.env.DOTFILES_TEST_UNDO_DIR
      vim.fn.chdir(vim.env.DOTFILES_TEST_PROJECT)
      dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/plugin/persistent_scratch.lua")
      local scratch = require("serranomorante.persistent_scratch")
      scratch.toggle()
      local bufnr = vim.api.nvim_get_current_buf()
      local key = utils.local_state_cwd_key(vim.fn.getcwd())
      local scratch_path = vim.fn.stdpath("state") .. "/persistent-scratch/" .. key .. ".md"
      assert(vim.api.nvim_buf_get_name(bufnr) == scratch_path, vim.api.nvim_buf_get_name(bufnr))
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert(#lines == 2 and lines[1] == "alpha" and lines[2] == "beta", vim.inspect(lines))
      vim.cmd.undo()
      lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert(#lines == 1 and lines[1] == "", vim.inspect(lines))
      vim.cmd.qa({ bang = true })
    '
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
