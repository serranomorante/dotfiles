local M = {}

---https://github.com/luukvbaal/nnn.nvim?tab=readme-ov-file#mappings
local mappings = {
  {
    "<C-g>", -- live grep in dir
    function(files)
      local dir = files[1]:match(".*/"):sub(0, -2)
      local read = io.open(dir:gsub("\\", ""), "r")

      if read ~= nil then
        io.close(read)
        local options = {
          ---https://github.com/ibhagwan/fzf-lua/wiki/Options#grep-providers-options
          search = " -- " .. vim.fn.fnamemodify(dir or "", ":~"),
          no_esc = true, -- Do not escape regex characters
        }
        require("fzf-lua").live_grep(options)
      end
    end,
  },
  {
    "<C-f>", -- find files in dir
    function(files)
      local dir = files[1]:match(".*/"):sub(0, -2)
      local read = io.open(dir:gsub("\\", ""), "r")

      if read ~= nil then
        io.close(read)
        require("fzf-lua").files({
          cwd = vim.fn.fnamemodify(dir or "", ":.:~"),
        })
      end
    end,
  },
}

local function opts()
  return {
    picker = {
      cmd = "nnn -JRHdaA",
      tabs = false,
      style = {
        width = 999,
        height = 999,
      },
    },
    replace_netrw = "picker",
    mappings = mappings,
    offset = true,
  }
end

local function keys() vim.keymap.set("n", "<leader>e", "<cmd>NnnPicker %:p<CR>", { desc = "NNN: toggle picker" }) end

function M.config()
  keys()
  require("nnn").setup(opts())
end

return M
