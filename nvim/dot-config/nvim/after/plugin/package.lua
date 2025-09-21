local function reload_package()
  vim.ui.select(vim.tbl_keys(package.loaded), {}, function(result)
    if not result then return end
    R(result)
  end)
end

vim.api.nvim_create_user_command(
  "ReloadPackage",
  reload_package,
  { force = true, nargs = "*", bar = true, desc = "Reload package" }
)
