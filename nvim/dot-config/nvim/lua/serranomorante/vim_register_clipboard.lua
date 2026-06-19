local M = {}

local namespace = "vim-registers"
local ttl_seconds = "2592000"

local function cachectl_bin()
  local repo_bin = vim.fs.joinpath(vim.env.HOME, "dotfiles", "utilities", "bin", "cachectl")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("cachectl") == 1 then return "cachectl" end
end

local function cache_key(regname)
  if regname == "" then return "unnamed" end
  if regname == '"' then return "unnamed" end
  if regname == "+" then return "plus" end
  if regname == "*" then return "star" end
  if regname == "-" then return "small-delete" end
  if regname:match("^[A-Z]$") then return regname:lower() end
  if regname:match("^[a-z0-9]$") then return regname end
end

local function register_text(event)
  if type(event.regcontents) ~= "table" then return "" end
  local text = table.concat(event.regcontents, "\n")
  if event.regtype == "V" then return text .. "\n" end
  return text
end

function M.store_yank(event)
  if event.operator ~= "y" then return end

  local key = cache_key(event.regname)
  if not key then return end

  local bin = cachectl_bin()
  if not bin then return end

  local text = register_text(event)
  vim.system({ bin, "set", namespace, key, ttl_seconds }, { stdin = text }, function(result)
    if result.code ~= 0 then
      vim.schedule(function() vim.notify("Could not export Vim register " .. event.regname, vim.log.levels.WARN) end)
    end
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Export yanked Vim registers to global register cache",
    group = vim.api.nvim_create_augroup("global_vim_registers", { clear = true }),
    callback = function() M.store_yank(vim.v.event) end,
  })
end

return M
