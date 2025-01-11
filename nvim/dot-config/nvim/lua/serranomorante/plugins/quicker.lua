local M = {}

local function keys()
  vim.keymap.set(
    "n",
    "<leader>qf",
    function()
      require("quicker").toggle({
        focus = false,
        open_cmd_mods = { split = "botright" },
      })
    end,
    { desc = "Quicker: toggle quickfix list" }
  )

  vim.keymap.set(
    "n",
    "<leader>ql",
    function() require("quicker").toggle({ focus = false, loclist = true }) end,
    { desc = "Quicker: toggle location list" }
  )
end

---@return quicker.SetupOptions
local opts = function()
  return {
    opts = {
      number = true,
    },
    highlight = {
      lsp = false,
      load_buffers = false, -- fixes issues with attaching coc keymaps
    },
    follow = {
      enabled = true,
    },
    on_qf = function(bufnr)
      vim.keymap.set("n", ">", function()
        local ok, _ = pcall(vim.cmd.cnewer)
        if not ok then return vim.notify("At the top of the quickfix stack", vim.log.levels.WARN) end
      end, { desc = "Quicker: go to next quickfix in history", nowait = true, buffer = bufnr })

      vim.keymap.set("n", "<", function()
        local ok, _ = pcall(vim.cmd.colder)
        if not ok then return vim.notify("At the bottom of the quickfix stack", vim.log.levels.WARN) end
      end, { desc = "Quicker: go to previous quickfix in history", nowait = true, buffer = bufnr })

      vim.keymap.set("n", "+", function()
        require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
        vim.api.nvim_win_set_height(0, math.min(20, vim.api.nvim_buf_line_count(0)))
      end, { desc = "Quicker: expand quickfix content", buffer = bufnr })

      vim.keymap.set(
        "n",
        "=",
        function() require("quicker").collapse() end,
        { desc = "Quicker: collapse quickfix content", buffer = bufnr }
      )

      vim.keymap.set(
        "n",
        "<C-l>",
        function() require("quicker").refresh() end,
        { desc = "Quicker: refresh quickfix content", buffer = bufnr }
      )
    end,
  }
end

M.config = function()
  keys()
  require("quicker").setup(opts())
end

return M
