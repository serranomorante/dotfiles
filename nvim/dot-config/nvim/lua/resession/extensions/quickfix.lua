local M = {}

M.on_save = function()
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
      }
    end,
    quickfix_list.items
  )
  return {
    title = quickfix_list.title,
    items = items,
  }
end

M.on_pre_load = function(data) vim.fn.setqflist({}, "r", { title = data.title, items = data.items or {} }) end

M.is_win_supported = function(winid, bufnr) return vim.bo[bufnr].buftype == "quickfix" end

M.save_win = function(winid) return {} end

M.load_win = function(winid, config)
  vim.api.nvim_set_current_win(winid)
  vim.cmd("copen")
  vim.api.nvim_win_close(winid, true)
  return vim.api.nvim_get_current_win()
end

return M
