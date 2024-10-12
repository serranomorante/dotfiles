local utils = require("serranomorante.utils")

local M = {}

---Choose a path to debug relative to project files (like package.json)
---Specially useful for monorepo setups
---@param files string[]
function M.pick_workspace_relative_to_file(files)
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

---Pick an `urlFilter` pattern from your current chromium tabs
function M.pick_url_filter_from_tabs()
  return coroutine.create(function(dap_run_co)
    local urls = utils.cmd({ "chrome-session-dump" })
    local items = vim.tbl_map(function(url)
      local choice_as_pattern = url:gsub("^https?://([^%/]*).*", "%1*")
      return choice_as_pattern
    end, vim.split(urls or "", "\n", { trimempty = true }))
    vim.ui.select(items, { label = "Pick url filter" }, function(choice)
      if choice then coroutine.resume(dap_run_co, choice) end
    end)
  end)
end

---@param config dap.Configuration
---@param on_config fun(config: dap.Configuration)
function M.python_enrich_config(config, on_config)
  local pythonPath = nil
  local venv_path = os.getenv("VIRTUAL_ENV")
  if venv_path then pythonPath = venv_path .. "/bin/python" end
  on_config(vim.tbl_deep_extend("force", config, {
    pythonPath = pythonPath,
  }))
end

return M
