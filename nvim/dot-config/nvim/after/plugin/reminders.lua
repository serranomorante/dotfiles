local utils = require("serranomorante.utils")

local REMIND_DIR = vim.env.HOME .. "/.config/remind"
local GENERATED_PATH = REMIND_DIR .. "/reminders.rem"
local NOTES_DIR = vim.env.HOME .. "/data/notes/foam"

local function shell_quote(value) return "'" .. value:gsub("'", [['"'"']]) .. "'" end

local function run_argv(value, metadata)
  if value == "agent" then
    if metadata.id then return { "agent", metadata.id } end
    vim.notify("Invalid remind @run agent: TODO is missing @id", vim.log.levels.ERROR)
    return nil
  end

  local argv = {}

  for token in value:gmatch("%S+") do
    if not token:match("^[A-Za-z0-9_.:-]+$") then return nil end
    table.insert(argv, token)
  end

  return #argv > 0 and argv or nil
end

local function add_substitution_filters(reminder)
  reminder = reminder .. " %b"
  if reminder:match(" AT ") then reminder = reminder .. " %1" end
  return reminder
end

local function reminder_to_msg(reminder, title)
  if reminder:match(" MSG ") or reminder:match(" RUN ") then return add_substitution_filters(reminder) end
  return add_substitution_filters(reminder .. " MSG " .. title)
end

local function reminder_to_run(reminder, argv)
  local command = { shell_quote(vim.env.HOME .. "/bin/remind-run") }
  for _, arg in ipairs(argv) do
    table.insert(command, shell_quote(arg))
  end
  return reminder .. " RUN " .. table.concat(command, " ")
end

local function agenda_metadata_comment(metadata, run)
  local fields = {}

  if run and run[1] then table.insert(fields, "run=" .. run[1]) end

  if metadata.tags then
    local tags = {}
    for tag in metadata.tags:gmatch("#[a-z][a-z0-9-]*") do
      table.insert(tags, tag)
    end
    if #tags > 0 then table.insert(fields, "tags=" .. table.concat(tags, ",")) end
  end

  if #fields == 0 then return nil end
  return "# remind-agenda-meta " .. table.concat(fields, " ")
end

local function markdown_files()
  local output = vim.fn.systemlist({ "rg", "--files", "--glob", "*.md", NOTES_DIR })
  if vim.v.shell_error ~= 0 then return {} end
  return vim.tbl_filter(function(path) return utils.foam_should_include_todo_source(path, NOTES_DIR) end, output)
end

local function parse_remind_block(lines, start_lnum)
  local block = {}
  local lnum = start_lnum + 1

  while lnum <= #lines do
    local line = lines[lnum]
    if line:match("^%s%s```%s*$") then return block, lnum end
    table.insert(block, (line:gsub("^%s%s", "")))
    lnum = lnum + 1
  end

  return block, lnum
end

local function reminder_items_for_block(title, block, metadata)
  local items = {}
  local run = nil

  for _, line in ipairs(block) do
    local candidate = line:match("^%s*@run%s+(.+)%s*$")
    if candidate then
      local argv = run_argv(candidate, metadata)
      if argv then
        run = argv
      else
        vim.notify("Invalid remind @run command: " .. candidate, vim.log.levels.ERROR)
      end
    elseif line:match("^%s*$") then
      -- skip blank lines in remind fences
    elseif line:match("^%s*REM%s") then
      local metadata_comment = agenda_metadata_comment(metadata, run)
      if metadata_comment then table.insert(items, metadata_comment) end
      table.insert(items, reminder_to_msg(line, title))
      if run then
        if metadata_comment then table.insert(items, metadata_comment) end
        table.insert(items, reminder_to_run(line, run))
      end
    else
      table.insert(items, line)
    end
  end

  return items
end

local function todo_metadata(lines, start_lnum, end_lnum)
  local metadata = {}

  for lnum = start_lnum + 1, end_lnum - 1 do
    local key, value = lines[lnum]:match("^%s*@([A-Za-z][A-Za-z0-9_-]*)%s+(.+)%s*$")
    if key then metadata[key:lower()] = value:gsub("%s+$", "") end
  end

  return metadata
end

local function has_remind_dir()
  if vim.fn.isdirectory(REMIND_DIR) == 0 then
    vim.notify("Missing " .. REMIND_DIR .. "; run ~/bin/dotfiles-stow PKM", vim.log.levels.ERROR)
    return false
  end

  return true
end

local function validate_generated_reminders()
  local once_arg = "-i$OnceFile=\"" .. vim.env.HOME .. "/.local/state/remind/oncefile\""
  local cmd = table.concat({
    "remind",
    shell_quote(once_arg),
    "-q",
    "-r",
    "-n",
    shell_quote(REMIND_DIR),
    "2>&1",
    ">/dev/null",
  }, " ")

  local output = vim.fn.system(cmd)
  local status = vim.v.shell_error
  output = vim.iter(vim.split(output, "\n", { plain = true }))
    :filter(function(line) return not line:match(": RUN disabled$") end)
    :totable()
  output = vim.trim(table.concat(output, "\n"))

  if output == "" then
    if status == 0 then return end
    output = "Remind validation failed with exit code " .. status
  end

  if status ~= 0 then error(output, 0) end

  vim.notify(output, vim.log.levels.WARN)
end

local function remind_update()
  local items = {}

  for _, path in ipairs(markdown_files()) do
    local lines = vim.fn.readfile(path)
    local lnum = 1
    local in_fence = false

    while lnum <= #lines do
      if lines[lnum]:match("^```") or lines[lnum]:match("^````") then
        in_fence = not in_fence
      elseif not in_fence then
        local title = lines[lnum]:match("^%- %[ %]%s+(.+)$")
        if title then
          title = title:gsub("\\%s*$", "")
          local search_lnum = lnum + 1

          while search_lnum <= math.min(#lines, lnum + 12) do
            if lines[search_lnum]:match("^%s%s```remind%s*$") then
              local block, end_lnum = parse_remind_block(lines, search_lnum)
              vim.list_extend(items, reminder_items_for_block(title, block, todo_metadata(lines, lnum, search_lnum)))
              lnum = end_lnum
              break
            end
            if lines[search_lnum]:match("^%- %[.?%]") then break end
            search_lnum = search_lnum + 1
          end
        end
      end

      lnum = lnum + 1
    end
  end

  utils.write_file(GENERATED_PATH, vim.fn.join(items, "\n"))
  validate_generated_reminders()
end

local function remind(args)
  if not has_remind_dir() then return end

  local default_flags = "-a -q"
  for _, arg in ipairs(args.fargs) do
    if arg == "-n" then
      default_flags = "-q"
      break
    end
  end
  local cmd = vim.fn.join({
    "remind '-i$OnceFile=\""
      .. vim.env.HOME
      .. "/.local/state/remind/oncefile\"' '-knotify-send %s &' "
      .. default_flags,
    unpack(args.fargs),
  }, " ")
  local content = vim.fn.system(vim.fn.join({ cmd, REMIND_DIR }, " "))
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
