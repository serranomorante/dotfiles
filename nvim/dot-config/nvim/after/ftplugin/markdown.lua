local utils = require("serranomorante.utils")
local lsp_utils = require("serranomorante.plugins.lsp.utils")
local markdown_images = require("serranomorante.markdown_images")

local bufnr = vim.api.nvim_get_current_buf()
local markdown_tags_ns = vim.api.nvim_create_namespace("serranomorante.markdown_tags")

local function is_markdown_tag(token)
  return token:match("^#[a-z][a-z0-9-]*$") and not token:find("%-%-") and not token:find("%-$")
end

local function refresh_markdown_tags()
  if vim.b[bufnr].large_buf then return end

  vim.api.nvim_buf_clear_namespace(bufnr, markdown_tags_ns, 0, -1)

  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local prefix, text = line:match("^(%s*@tags%s+)(.-)%s*$")
    if text and text ~= "" then
      local tag_line = true

      for token in text:gmatch("%S+") do
        if not is_markdown_tag(token) then
          tag_line = false
          break
        end
      end

      if tag_line then
        for start_col, tag in text:gmatch("()(#[a-z][a-z0-9-]*)") do
          local col = #prefix + start_col - 1
          vim.api.nvim_buf_set_extmark(bufnr, markdown_tags_ns, lnum - 1, col, {
            end_col = col + #tag,
            hl_group = "CustomMarkdownTag",
            priority = 200,
          })
        end
      end
    end
  end
end

---Fill title to markdown files that don't have it
if vim.fn.empty(select(1, unpack(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)))) == 1 then
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if utils.exists(bufname) then
    local f = vim.fn.split(vim.fn.fnamemodify(bufname, ":t"), "\\.")
    table.remove(f) -- remove the `.md` part
    local fd = assert(vim.uv.fs_open(bufname, "w", 420))
    vim.uv.fs_write(fd, "# " .. vim.fn.join(vim.tbl_map(function(i) return i:gsub("^%l", string.upper) end, f), " | "))
    vim.uv.fs_close(fd)
  end
end

lsp_utils.enable("marksman", bufnr)

markdown_images.attach(bufnr)

local markdown_tags_group =
  vim.api.nvim_create_augroup(("serranomorante_markdown_tags_%d"):format(bufnr), { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
  desc = "Highlight personal markdown tag lines",
  buffer = bufnr,
  group = markdown_tags_group,
  callback = refresh_markdown_tags,
})
refresh_markdown_tags()

if vim.bo[bufnr].filetype == "markdown.system_health" then
  vim.bo[bufnr].readonly = true
  vim.bo[bufnr].modifiable = false
end
