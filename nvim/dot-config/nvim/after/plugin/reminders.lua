local utils = require("serranomorante.utils")

local PATH = vim.env.HOME .. "/.config/remind/reminders.rem"

local function remind_update()
  local pattern =
    "'^- \\[ \\]\\s([^\\n\\\\]+)(?:\\n|\\\\\n)(?:^\\n|^\\s{2}[^\\n]+\\n){1,10}\\s{2}```remind\\n(.*?)\\n\\s{2}```'"
  local replace = "'$2 MSG \"$1\"'"
  local flags = "--multiline --multiline-dotall --no-filename --no-line-number --no-column -r " .. replace
  local matches = vim.fn.split(utils.grep_with_rg(string.format("%s %s", pattern, flags)), ",")
  local items = {}
  ---Assigns the same title to remind blocks with multiple lines
  for i, remind_match in ipairs(matches) do
    if not remind_match:match(" MSG ") then
      local count = i
      while not matches[count]:match(" MSG ") do
        count = count + 1
      end
      local start, finish = (matches[count]):find("MSG.*")
      remind_match = string.format("%s %s", remind_match, matches[count]:sub(start, finish))
    end
    table.insert(items, remind_match)
  end
  utils.write_file(PATH, vim.fn.join(items, "\n"))
  vim.schedule(function()
    vim.api.nvim_echo({ { "Reminder database updated", "DiagnosticOk" } }, false, {})
    vim.fn.system(string.format("scp %s phone2:/data/data/com.termux/files/home/%s &", PATH, PATH:sub(#vim.env.HOME + 1)))
  end)
end

local function remind()
  vim.fn.system("/usr/bin/remind '-i$OnceFile=\"~/.config/remind/oncefile\"' '-knotify-send %s &' -a -q " .. PATH)
end

vim.api.nvim_create_user_command(
  "RemindUpdate",
  remind_update,
  { force = true, nargs = "*", desc = "Update list of reminders" }
)
vim.api.nvim_create_user_command("Remind", remind, { force = true, nargs = "*", desc = "Run remind command" })
