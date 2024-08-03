local M = {}

---Choose a path to debug relative to specific files
---Specially useful for monorepo setups
---@param files string[]
M.choose_path_relative_to_file = function(files)
  local workspaceFolder = vim.fn.getcwd()
  workspaceFolder = workspaceFolder:sub(-1) ~= "/" and workspaceFolder .. "/" or workspaceFolder
  return coroutine.create(function(dap_run_co)
    local paths = vim.fs.find(files, {
      stop = workspaceFolder .. "..",
      type = "file",
      upward = true,
      path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
    })
    local items = vim.tbl_map(function(path)
      local dirname = vim.fn.fnamemodify(path, ":p:h"):sub(#workspaceFolder + 1, -1)
      if dirname == "" then return workspaceFolder end
      return dirname
    end, paths)
    vim.ui.select(items, { label = workspaceFolder }, function(choice)
      if choice then coroutine.resume(dap_run_co, workspaceFolder .. choice) end
    end)
  end)
end

return M
