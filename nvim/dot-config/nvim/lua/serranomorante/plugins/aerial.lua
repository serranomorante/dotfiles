local M = {}

local function keys()
  vim.keymap.set(
    { "n", "x" },
    "<leader>ls",
    function() require("aerial").toggle() end,
    { desc = "Aerial: toggle document symbols" }
  )
end

local function opts()
  return {
    show_guides = true,
    filter_kind = false,
    disable_max_lines = vim.g.max_file.lines,
    disable_max_size = vim.g.max_file.size,
    highlight_on_jump = 1000,
    backends = { "treesitter" }, -- less headaches
    manage_folds = false,
    link_folds_to_tree = false,
    link_tree_to_folds = false,
    layout = {
      default_direction = "float",
      min_width = 0.9,
      win_opts = {
        winhl = "Normal:CustomAerialBg,NormalFloat:CustomAerialBg,Title:CustomAerialTitle",
      },
    },
    float = {
      border = "solid",
      relative = "editor",
      override = function(conf, source_winid)
        conf.title = "Document symbols"
        return conf
      end,
    },
    keymaps = {
      ["l"] = false, -- tree_open
      ["L"] = false, -- tree_open_recursive
      ["h"] = false, -- tree_close
      ["H"] = false, -- tree_close_recursive
      ["zx"] = false, -- tree_sync_folds
      ["zX"] = false, -- tree_sync_folds
    },
  }
end

function M.config()
  keys()
  require("aerial").setup(opts())
end

return M
