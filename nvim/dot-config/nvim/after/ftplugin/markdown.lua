local coc_utils = require("serranomorante.plugins.coc.utils")
local lsp_utils = require("serranomorante.plugins.lsp.utils")

local bufnr = vim.api.nvim_get_current_buf()

---Fill title to markdown files that don't have it
if vim.fn.empty(select(1, unpack(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)))) == 1 then
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if vim.fn.filereadable(bufname) == 1 then
    local f = vim.fn.split(vim.fn.fnamemodify(bufname, ":t"), "\\.")
    table.remove(f) -- remove the `.md` part
    local fd = assert(vim.uv.fs_open(bufname, "w", 420))
    vim.uv.fs_write(fd, "# " .. vim.fn.join(vim.tbl_map(function(i) return i:gsub("^%l", string.upper) end, f), " | "))
    vim.uv.fs_close(fd)
  end
end

if coc_utils.should_enable(bufnr) then
  require("serranomorante.plugins.coc").start(nil, { bufnr = bufnr })
elseif lsp_utils.should_enable(bufnr) then
  vim.lsp.enable("marksman")
  vim.api.nvim_exec_autocmds("FileType", { group = "nvim.lsp.enable" })
else
  require("serranomorante.plugins.nvim-ufo").config()
end
