local utils = require("serranomorante.utils")

local FILE = vim.env.HOME .. "/.config/remind/reminders.rem"

local function remind_update()
  local pattern =
    "'^- \\[ \\]\\s([^\\n\\\\]+)(?:\\n|\\\\\n)(?:^\\n|^\\s{2}[^\\n]+\\n){1,10}\\s{2}```remind\\n(.*?)\\n\\s{2}```'"
  local replace = "'$2 MSG \"$1\"'"
  local flags = "--multiline --multiline-dotall --no-filename --no-line-number --no-column -r " .. replace
  local match = utils.grep_with_rg(string.format("%s %s", pattern, flags))
  ---@cast match string
  match = string.format('SET $OnceFile "%s/.config/remind/oncefile"\n\n%s', vim.env.HOME, match)
  utils.write_file(FILE, vim.fn.join(vim.fn.split(match, ","), "\n"))
  vim.schedule(function() vim.api.nvim_echo({ { "Reminder database updated", "DiagnosticOk" } }, false, {}) end)
end

local function remind() vim.fn.system("/usr/bin/remind '-knotify-send %s &' -a -q " .. FILE) end

vim.api.nvim_create_user_command(
  "RemindUpdate",
  remind_update,
  { force = true, nargs = "*", desc = "Update list of reminders" }
)
vim.api.nvim_create_user_command("Remind", remind, { force = true, nargs = "*", desc = "Run remind command" })
