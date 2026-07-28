#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim integration headless firejail lsp marksman
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim/runtime
# dotfiles-test-case: markdown-block-ids-marksman-diagnostics-filter-integrated

# Purpose: Load the active Neovim configuration and verify Marksman diagnostics
# still treat Markdown #^ block-id links as handled by the local @id feature.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

prepare_lsp_config() {
    test_config="${DOTFILES_TEST_TMP}/nvim-config"
    mkdir -p "${test_config}/lua/serranomorante"
    cat >"${test_config}/lua/serranomorante/binaries.lua" <<'LUA'
return {
  marksman = function() return "/usr/bin/marksman" end,
}
LUA
}

run_nvim_lua() {
    local lua_file=$1
    VIMRUNTIME=/home/aaaa/.local/share/nvim/runtime "$nvim_bin" --headless -u NONE -c "set rtp^=${rtp}" -c "set rtp^=${test_config}" -S "$lua_file"
}

case "${DOTFILES_TEST_CASE:-}" in
markdown-block-ids-marksman-diagnostics-filter-integrated)
    prepare_lsp_config
    lua_file="${DOTFILES_TEST_TMP}/marksman-diagnostics-filter.lua"
    cat >"$lua_file" <<'LUA'
local function main()
local root = vim.env.DOTFILES_TEST_TMP .. "/marksman-diagnostics-filter"
vim.fn.mkdir(root, "p")
vim.fn.writefile({}, root .. "/.marksman.toml")
vim.fn.writefile({ "Target paragraph", "@id todo-dotfiles-testing-plan" }, root .. "/personal.todos.md")
vim.fn.writefile({
  "Today [[personal.todos#^todo-dotfiles-testing-plan]]",
  "",
  "Broken heading [[personal.todos#missing-heading]]",
}, root .. "/a.md")

vim.g.lsp_enabled = true
require("serranomorante.plugins.lsp").config()
vim.lsp.config("marksman", dofile(vim.env.DOTFILES_TEST_ROOT .. "/nvim/dot-config/nvim/after/lsp/marksman.lua"))
vim.cmd.edit(root .. "/a.md")
vim.bo.filetype = "markdown"
require("serranomorante.plugins.lsp.utils").enable("marksman", 0)

local function diagnostic_messages()
  return vim.tbl_map(function(diagnostic) return diagnostic.message or "" end, vim.diagnostic.get(0))
end

local function has_message(pattern)
  return vim.iter(diagnostic_messages()):any(function(message) return message:find(pattern, 1, true) ~= nil end)
end

local function diagnostics_summary()
  local messages = diagnostic_messages()
  if #messages == 0 then return "<no diagnostics>" end
  return table.concat(messages, " | ")
end

local marksman_attached = vim.wait(10000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "marksman" }) > 0
end, 100)
assert(marksman_attached, "marksman did not attach to the Markdown buffer")

local diagnostics_settled = vim.wait(10000, function()
  return has_message("missing-heading") and not has_message("todo-dotfiles-testing-plan")
end, 100)
assert(diagnostics_settled, "Marksman diagnostics did not settle into the expected filtered state: " .. diagnostics_summary())
for _, client in ipairs(vim.lsp.get_clients({ name = "marksman" })) do
  client:stop(false)
end
if not vim.wait(2000, function() return #vim.lsp.get_clients({ name = "marksman" }) == 0 end, 100) then
  for _, client in ipairs(vim.lsp.get_clients({ name = "marksman" })) do
    client:stop(true)
  end
end
vim.cmd.qa({ bang = true })
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
  print(err)
  vim.cmd.cquit({ bang = true })
end
LUA
    run_nvim_lua "$lua_file"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
