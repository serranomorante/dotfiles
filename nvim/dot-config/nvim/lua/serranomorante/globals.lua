_G.user = _G.user or {}
---https://github.com/stevearc/resession.nvim/issues/44#issuecomment-2027345600
function P(v) vim.cmd.echom({ args = { vim.fn.string(vim.inspect(v)) }, mods = { unsilent = true } }) end

function RELOAD(module_name, starts_with_only)
  if starts_with_only == nil then starts_with_only = true end

  for loaded_name, _ in pairs(package.loaded) do
    local matches = starts_with_only and loaded_name:sub(1, #module_name) == module_name
      or loaded_name:find(module_name, 1, true)
    if matches then package.loaded[loaded_name] = nil end
  end

  if vim.loader and vim.loader.reset then vim.loader.reset() end
end

function R(name)
  RELOAD(name)
  return require(name)
end
