local M = {}

--- An `init` function to build multiple update events which is not supported yet by Heirline's update field
---https://github.com/rebelot/heirline.nvim/issues/71#issue-1402412655
---@param opts any[] an array like table of autocmd events as either just a string or a table with custom patterns and callbacks.
---@return function # The Heirline init function
-- @usage local heirline_component = { init = require("astronvim.utils.status").init.update_events { "BufEnter", { "User", pattern = "LspProgressUpdate" } } }
function M.update_events(opts)
  if not vim.islist(opts) then opts = { opts } end
  return function(self)
    if not rawget(self, "once") then
      local function clear_cache() self._win_cache = nil end
      for _, event in pairs(opts) do
        local event_opts = { callback = clear_cache }
        if type(event) == "table" then
          event_opts.pattern = event.pattern
          if event.callback then
            local callback = event.callback
            function event_opts.callback(args)
              clear_cache()
              callback(self, args)
            end
          end
          event = event[1]
        end
        vim.api.nvim_create_autocmd(event, event_opts)
      end
      self.once = true
    end
  end
end

function M.setup_colors()
  local background = vim.api.nvim_get_option_value("background", {}) == "dark" and "NvimDark" or "NvimLight"
  return {
    modifiable_tabline_fg = background .. "Yellow",
    modifiable_statusline_fg = background .. "Yellow",
    modified_statusline_fg = background .. "Grey1",
    modified_tabline_fg = "Black",
    diagnostic_error_fg = background .. "Red",
    diagnostic_warn_fg = background .. "Yellow",
    diagnostic_info_fg = background .. "Cyan",
    diagnostic_hint_fg = background .. "Blue",
    git_added_fg = background .. "Green",
    git_removed_fg = background .. "Red",
    git_changed_fg = background .. "Cyan",
    dap_message_stopped_fg = background .. "Red",
  }
end

return M
