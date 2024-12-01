local wezterm = require("wezterm")

local config = {}

if wezterm.config_builder then config = wezterm.config_builder() end

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 500
config.animation_fps = 1
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"

config.font = wezterm.font("Pragmasevka Nerd Font ")
config.font_size = 18.0
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.hide_tab_bar_if_only_one_tab = true
config.disable_default_key_bindings = true
config.adjust_window_size_when_changing_font_size = false
config.keys = {
  {
    key = "V",
    mods = "CTRL",
    action = wezterm.action.PasteFrom("Clipboard"),
  },
  {
    key = "=",
    mods = "CTRL",
    action = wezterm.action.IncreaseFontSize,
  },
  {
    key = "-",
    mods = "CTRL",
    action = wezterm.action.DecreaseFontSize,
  },
  {
    key = "0",
    mods = "CTRL",
    action = wezterm.action.ResetFontSize,
  },
}

return config
