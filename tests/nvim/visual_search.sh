#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless search
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: nvim-visual-search-repeat-scopes-to-selection
# dotfiles-test-case: nvim-visual-search-reverse-repeat-scopes-to-selection
# dotfiles-test-case: nvim-normal-search-repeat-no-wrap-does-not-raise-lua-error
# dotfiles-test-case: nvim-normal-search-reverse-repeat-no-wrap-does-not-raise-lua-error

# Purpose: Verify visual-mode n/N repeats scope searches to the active selection without polluting normal repeats.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    NVIM_LOG_FILE="${DOTFILES_TEST_TMP}/nvim.log" "$nvim_bin" --headless -n -u NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

case "${DOTFILES_TEST_CASE:-}" in
nvim-visual-search-repeat-scopes-to-selection)
    run_nvim_lua 'local function main()
  require("serranomorante.remap")
  vim.opt.shortmess:append("S")
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  local lines = {}
  for i = 1, 10 do
    lines[i] = string.format("%02d aliases", i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.modified = false
  vim.fn.setreg("/", "aliases")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  end

  local function assert_line(expected, context)
    assert(vim.api.nvim_win_get_cursor(0)[1] == expected, context .. " should visit line " .. expected .. ", got " .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
  end

  for expected = 1, 4 do
    press("n")
    assert_line(expected, "normal n")
  end

  vim.cmd.normal({ "5GV3j", bang = true })
  for _, expected in ipairs({ 5, 6, 7, 8, 5, 6 }) do
    press("n")
    assert_line(expected, "visual n scoped to lines 5-8")
    assert(vim.fn.getreg("/") == "aliases", "temporary visual prefix leaked into search register: " .. vim.fn.getreg("/"))
  end

  press("<Esc>")
  press("n")
  assert_line(7, "normal n after clearing visual selection")
  press("N")
  assert_line(6, "normal N after clearing visual selection")
  assert(vim.fn.getreg("/") == "aliases", "normal search register should remain unscoped, got " .. vim.fn.getreg("/"))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    ;;
nvim-visual-search-reverse-repeat-scopes-to-selection)
    run_nvim_lua 'local function main()
  require("serranomorante.remap")
  vim.opt.shortmess:append("S")
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  local lines = {}
  for i = 1, 10 do
    lines[i] = string.format("%02d aliases", i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.modified = false
  vim.fn.setreg("/", "aliases")
  vim.api.nvim_win_set_cursor(0, { 9, 3 })

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  end

  local function assert_line(expected, context)
    assert(vim.api.nvim_win_get_cursor(0)[1] == expected, context .. " should visit line " .. expected .. ", got " .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
  end

  for _, expected in ipairs({ 8, 7, 6, 5 }) do
    press("N")
    assert_line(expected, "normal N")
  end

  vim.cmd.normal({ "5GV3j", bang = true })
  for _, expected in ipairs({ 7, 6, 5, 8, 7, 6 }) do
    press("N")
    assert_line(expected, "visual N scoped to lines 5-8")
    assert(vim.fn.getreg("/") == "aliases", "temporary visual prefix leaked into search register: " .. vim.fn.getreg("/"))
  end

  press("<Esc>")
  press("N")
  assert_line(5, "normal N after clearing visual selection")
  press("n")
  assert_line(6, "normal n after clearing visual selection")
  assert(vim.fn.getreg("/") == "aliases", "normal search register should remain unscoped, got " .. vim.fn.getreg("/"))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    ;;
nvim-normal-search-repeat-no-wrap-does-not-raise-lua-error)
    run_nvim_lua 'local function main()
  require("serranomorante.remap")
  vim.opt.shortmess:append("S")
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  vim.o.wrapscan = false
  local lines = {}
  for i = 1, 10 do
    lines[i] = string.format("%02d aliases", i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.modified = false
  vim.fn.setreg("/", "aliases")
  vim.api.nvim_win_set_cursor(0, { 10, 3 })
  vim.v.errmsg = ""
  vim.api.nvim_feedkeys("n", "x", false)
  assert(not vim.v.errmsg:find("E5108", 1, true), "normal n fallback should not raise Lua callback errors, got " .. vim.v.errmsg)
  assert(not vim.v.errmsg:find("serranomorante/remap.lua", 1, true), "normal n fallback should not expose remap.lua stack traces, got " .. vim.v.errmsg)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 10, "normal n at bottom with nowrapscan should keep cursor on line 10, got " .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
  assert(vim.fn.getreg("/") == "aliases", "normal search register should remain unscoped, got " .. vim.fn.getreg("/"))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    ;;
nvim-normal-search-reverse-repeat-no-wrap-does-not-raise-lua-error)
    run_nvim_lua 'local function main()
  require("serranomorante.remap")
  vim.opt.shortmess:append("S")
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  vim.o.wrapscan = false
  local lines = {}
  for i = 1, 10 do
    lines[i] = string.format("%02d aliases", i)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.modified = false
  vim.fn.setreg("/", "aliases")
  vim.api.nvim_win_set_cursor(0, { 1, 3 })
  vim.v.errmsg = ""
  vim.api.nvim_feedkeys("N", "x", false)
  assert(not vim.v.errmsg:find("E5108", 1, true), "normal N fallback should not raise Lua callback errors, got " .. vim.v.errmsg)
  assert(not vim.v.errmsg:find("serranomorante/remap.lua", 1, true), "normal N fallback should not expose remap.lua stack traces, got " .. vim.v.errmsg)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 1, "normal N at top with nowrapscan should keep cursor on line 1, got " .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
  assert(vim.fn.getreg("/") == "aliases", "normal search register should remain unscoped, got " .. vim.fn.getreg("/"))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
