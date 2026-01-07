local function switch_color_mode(command_args)
  if not vim.list_contains({ "light", "dark" }, command_args.args) then return end
  vim.api.nvim_set_option_value("background", command_args.args, {})
  vim.cmd.runtime({ "colors/default.lua", bang = true })
end

vim.api.nvim_create_user_command("ColorMode", switch_color_mode, {
  force = true,
  nargs = "*",
  bar = true,
  desc = "Change color mode (light, dark)",
})

---Sync color mode on startup based on system colorscheme
vim.schedule(function()
  local color_mode = vim.fn.system('grep "ColorScheme=" ~/.config/kdeglobals | cut -d "=" -f2')
  switch_color_mode({ args = color_mode == "BreezeDark\n" and "dark" or "light" })
end)
