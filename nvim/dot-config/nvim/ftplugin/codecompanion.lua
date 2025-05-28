local buffer = vim.api.nvim_get_current_buf()
local winid = vim.api.nvim_get_current_win()
local repl_ns = vim.api.nvim_create_namespace("codecompanion-hl" .. buffer)
local group = vim.api.nvim_create_augroup("codecompanion-hl" .. buffer, { clear = true })

local function is_same_filetype(buf1, buf2)
  return vim.api.nvim_get_option_value("filetype", { buf = buf1 })
    == vim.api.nvim_get_option_value("filetype", { buf = buf2 })
end

vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter", "WinEnter" }, {
  desc = "Change window background color for codecompanion",
  buffer = buffer,
  group = group,
  callback = function(args)
    if not is_same_filetype(args.buf, buffer) then return end
    vim.api.nvim_set_hl(repl_ns, "Normal", { link = "CustomAIChatBg" })
    vim.api.nvim_win_set_hl_ns(0, repl_ns)
  end,
})

vim.api.nvim_create_autocmd("BufLeave", {
  desc = "Reset window background color when leaving codecompanion",
  buffer = buffer,
  group = group,
  callback = function(args)
    local current_winid = vim.api.nvim_get_current_win()
    if current_winid + args.buf ~= winid + buffer and #vim.api.nvim_tabpage_list_wins(0) > 1 then return end
    vim.api.nvim_set_hl(repl_ns, "Normal", {})
    vim.api.nvim_win_set_hl_ns(0, repl_ns)
  end,
})
