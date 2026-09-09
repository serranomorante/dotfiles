local utils = require("serranomorante.utils")

local M = {}

local MARK_LETTERS = {}
for i = 65, 90 do MARK_LETTERS[#MARK_LETTERS + 1] = string.char(i) end

local function label_key(letter) return letter .. "-label" end

---@return string?
local function marks_label_bin()
  local configured = vim.env.MARK_LABEL_BIN
  if configured and configured ~= "" and vim.fn.executable(configured) == 1 then return configured end

  local repo_bin = utils.join_paths(vim.env.HOME, "dotfiles", "utilities", "bin", "marks-label")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("marks-label") == 1 then return "marks-label" end
end

local function scope() return utils.local_state_cwd_key() end

---@return table<string, string> label_key -> label
local function labels()
  local result = {}
  local bin = marks_label_bin()
  if not bin then return result end

  local out = vim.fn.system({ bin, "list", scope() })
  if vim.api.nvim_get_vvar("shell_error") ~= 0 then return result end

  for line in (out .. "\n"):gmatch("(.-)\n") do
    local key, value = line:match("^(%S-)\t(.*)$")
    if key then result[key] = value end
  end
  return result
end

---@return table<string, { file: string, pos: integer[], label: string? }> letter -> mark
local function global_marks()
  local label_map = labels()
  local marks = {}
  for _, item in ipairs(vim.fn.getmarklist()) do
    local letter = item.mark:match("^'([A-Z])$")
    if letter then marks[letter] = { file = item.file, pos = item.pos, label = label_map[label_key(letter)] } end
  end
  return marks
end

local function set_label(letter, label)
  local bin = marks_label_bin()
  if not bin then return end

  local value = vim.trim(label or "")
  if value == "" then
    vim.fn.system({ bin, "clear", scope(), label_key(letter) })
  else
    vim.fn.system({ bin, "set", scope(), label_key(letter), value })
  end
end

---Save or reassign a global mark with an optional label.
function M.set()
  local current = global_marks()
  vim.ui.select(MARK_LETTERS, {
    prompt = "Set global mark",
    ---@param letter string
    format_item = function(letter)
      local mark = current[letter]
      if mark then return string.format("%s | %s", mark.label or letter, mark.file) end
      return letter
    end,
  }, function(letter)
    if not letter then return end

    vim.cmd.normal({ "m" .. letter, bang = true })
    vim.ui.input({
      prompt = "Label for mark " .. letter .. " (empty keeps current): ",
      default = current[letter] and current[letter].label or "",
    }, function(input)
      if input == nil then return end
      set_label(letter, input)
      vim.notify(string.format("[marks] saved mark %s", vim.trim(input) ~= "" and input or letter))
    end)
  end)
end

---Jump to a labelled global mark through the picker.
function M.jump()
  local current = global_marks()
  local entries = {}
  for _, letter in ipairs(MARK_LETTERS) do
    if current[letter] then entries[#entries + 1] = letter end
  end

  if #entries == 0 then
    vim.notify("[marks] no global marks set", vim.log.levels.WARN)
    return
  end

  vim.ui.select(entries, {
    prompt = "Go to mark",
    ---@param letter string
    format_item = function(letter)
      local mark = current[letter]
      return string.format("%s | %s:%d", mark.label or letter, mark.file, mark.pos[2])
    end,
  }, function(letter)
    if not letter then return end
    vim.cmd.normal({ "`" .. letter, bang = true })
    vim.cmd.normal({ "zz", bang = true })
    vim.notify(string.format("[marks] go to mark: %s", current[letter].label or letter))
  end)
end

---@return table<string, { file: string, pos: integer[], label: string? }> letter -> mark
function M.list() return global_marks() end

---Delete a global mark and its label.
function M.delete()
  local current = global_marks()
  local entries = {}
  for _, letter in ipairs(MARK_LETTERS) do
    if current[letter] then entries[#entries + 1] = letter end
  end

  if #entries == 0 then
    vim.notify("[marks] no global marks set", vim.log.levels.WARN)
    return
  end

  vim.ui.select(entries, {
    prompt = "Delete mark",
    ---@param letter string
    format_item = function(letter)
      local mark = current[letter]
      return string.format("%s | %s", mark.label or letter, mark.file)
    end,
  }, function(letter)
    if not letter then return end
    vim.cmd.delmarks(letter)
    set_label(letter, "")
    vim.notify(string.format("[marks] deleted mark %s", letter))
  end)
end

return M
