local utils = require("serranomorante.utils")

local M = {}

function M.on_save()
  local quickfix_list = vim.fn.getqflist({ all = true })
  local items = vim.tbl_map(
    function(item)
      return {
        filename = item.bufnr and vim.api.nvim_buf_get_name(item.bufnr),
        module = item.module,
        lnum = item.lnum,
        end_lnum = item.end_lnum,
        col = item.col,
        end_col = item.end_col,
        vcol = item.vcol,
        nr = item.nr,
        pattern = item.pattern,
        text = item.text,
        type = item.type,
        valid = item.valid,
        user_data = item.user_data,
      }
    end,
    quickfix_list.items
  )
  return {
    title = quickfix_list.title,
    context = quickfix_list.context,
    items = items,
  }
end

function M.on_pre_load(data)
  vim.fn.setqflist({}, "r", { title = data.title, items = data.items or {}, context = data.context })
end

function M.is_win_supported(winid, bufnr) return vim.bo[bufnr].buftype == "quickfix" end

function M.save_win(winid) return {} end

function M.load_win(winid, config)
  if vim.fn.winnr("$") == 1 then return vim.api.nvim_get_current_win() end -- fixes unwanted fullscreen qf list
  vim.api.nvim_set_current_win(winid)
  utils.open_qflist()
  vim.api.nvim_win_close(winid, true)
  return vim.api.nvim_get_current_win()
end

return M
