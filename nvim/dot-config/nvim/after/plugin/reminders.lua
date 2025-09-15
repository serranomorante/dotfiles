local utils = require("serranomorante.utils")

local PATH = vim.env.HOME .. "/.config/remind/reminders.rem"

local function remind_update()
  local pattern =
    "'^- \\[ \\]\\s([^\\n\\\\]+)(?:\\n|\\\\\n)(?:^\\n|^\\s{2}[^\\n]+\\n){1,10}\\s{2}```remind\\n(.*?)\\n\\s{2}```'"
  local replace = "'$2 MSG $1'"
  local flags = "--multiline --multiline-dotall --no-filename --no-line-number --no-column -r " .. replace
  local matches = vim.fn.split(utils.grep_with_rg(string.format("%s %s", pattern, flags)), ",")
  local items = {}
  ---Assigns the same title to remind blocks with multiple lines
  for i, remind_match in ipairs(matches) do
    if not remind_match:match(" MSG ") and not remind_match:match("PUSH%-OMIT%-CONTEXT") then
      local count = i
      while not matches[count]:match(" MSG ") do
        count = count + 1
      end
      local start, finish = (matches[count]):find("MSG.*")
      remind_match = string.format("%s %s", remind_match, matches[count]:sub(start, finish))
    end
    ---Removes msg on POP-OMIT-CONTEXT
    if remind_match:match("POP%-OMIT%-CONTEXT MSG") then remind_match = remind_match:sub(1, #"  POP-OMIT-CONTEXT") end
    ---Removes double MSG
    if select(2, remind_match:gsub("MSG", "")) > 1 then
      local start = remind_match:find("MSG", remind_match:find("MSG") + 2)
      remind_match = remind_match:sub(1, start - 2) -- 2 due to the 2 space indent on each line
    end
    ---Add substitution filters when necessary
    remind_match = remind_match .. " %b"
    if remind_match:match(" AT ") then remind_match = remind_match .. " %1" end
    table.insert(items, remind_match)
  end
  utils.write_file(PATH, vim.fn.join(items, "\n"))
  vim.schedule(function()
    vim.api.nvim_echo({ { "Reminder database updated", "DiagnosticOk" } }, false, {})
    vim.fn.system(
      string.format("scp %s phone2:/data/data/com.termux/files/home/%s &", PATH, PATH:sub(#vim.env.HOME + 1))
    )
  end)
end

local function remind(args)
  local cmd = vim.fn.join({
    "remind '-i$OnceFile=\"~/.config/remind/oncefile\"' '-knotify-send %s &' -a -q",
    unpack(args.fargs),
  }, " ")
  local content = vim.fn.system(vim.fn.join({ cmd, PATH }, " "))
  if content then return vim.api.nvim_echo({ { content, "DiagnosticWarn" } }, false, {}) end
end

vim.api.nvim_create_user_command(
  "RemindUpdate",
  remind_update,
  { force = true, nargs = "*", desc = "Update list of reminders" }
)

vim.api.nvim_create_user_command(
  "Remind",
  remind,
  { force = true, nargs = "*", bar = true, desc = "Run remind command" }
)
