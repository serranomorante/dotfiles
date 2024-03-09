local utils = require("serranomorante.utils")

return {
  name = "Toggle Lazygit",
  builder = function()
    local worktree = utils.file_worktree()
    local args = {}

    if worktree ~= nil then
      table.insert(args, ("--work-tree=%s"):format(worktree.toplevel))
      table.insert(args, ("--git-dir=%s"):format(worktree.gitdir))
    end

    return {
      name = "lazygit",
      cmd = { "lazygit" },
      args = args,
      components = { "default" },
    }
  end,
  tags = { "editor" },
  condition = {
    callback = function() return vim.fn.executable("lazygit") == 1 end,
  },
}
