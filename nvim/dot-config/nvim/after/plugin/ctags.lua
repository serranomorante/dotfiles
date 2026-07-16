local utils = require("serranomorante.utils")

local active_tag_references

local function rg_escape(text) return (text:gsub("([\\^$%.%[%]%(%)%*%+%?%{%}|])", "\\%1")) end

local function rg_search_arg(pattern) return "'" .. pattern:gsub("'", "\\x27") .. "'" end

local function unique_names(names)
  local seen = {}
  local result = {}
  for _, name in ipairs(names) do
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(result, name)
    end
  end
  return result
end

local function tag_name_under_cursor()
  local name = vim.fn.expand("<cword>")
  if name == "" then
    vim.api.nvim_echo({ { "No tag name under cursor" } }, false, { err = true })
    return nil
  end
  return name
end

local function tags_file()
  local buffer_path = vim.api.nvim_buf_get_name(0)
  if buffer_path ~= "" then
    local found = vim.fn.findfile("tags", vim.fn.fnamemodify(buffer_path, ":p:h") .. ";")
    if found ~= "" then return vim.fn.fnamemodify(found, ":p") end
  end

  local project_tags = vim.fs.joinpath(utils.git_root_or_cwd(), "tags")
  if vim.fn.filereadable(project_tags) == 1 then return project_tags end
  return nil
end

local function parse_tag_line(line, name)
  if line:sub(1, 1) == "!" then return nil end

  local parts = vim.split(line, "\t", { plain = true })
  if parts[1] ~= name or not parts[2] or not parts[3] then return nil end

  local tag = {
    name = parts[1],
    filename = parts[2],
    cmd = parts[3],
    kind = parts[4],
  }

  for index = 5, #parts do
    local key, value = parts[index]:match("^([^:]+):(.*)$")
    if key then tag[key] = value end
  end

  if tag.line then tag.line = tonumber(tag.line) or tag.line end
  return tag
end

local function tag_absolute_filename(tag, tagfile)
  if not tag.filename then return nil end
  if vim.fn.fnamemodify(tag.filename, ":p") == tag.filename then return vim.fs.normalize(tag.filename) end
  return vim.fs.normalize(vim.fs.joinpath(vim.fn.fnamemodify(tagfile, ":p:h"), tag.filename))
end

local function select_tag(tags, tagfile)
  local buffer_path = vim.api.nvim_buf_get_name(0)
  if buffer_path ~= "" then
    local absolute_buffer_path = vim.fs.normalize(vim.fn.fnamemodify(buffer_path, ":p"))
    for _, tag in ipairs(tags) do
      if tag_absolute_filename(tag, tagfile) == absolute_buffer_path then return tag end
    end
  end

  return tags[1]
end

local function tag_target_line(tag, tagfile)
  local filename = tag_absolute_filename(tag, tagfile)
  if not filename or type(tag.line) ~= "number" or vim.fn.filereadable(filename) ~= 1 then return nil end
  return vim.fn.readfile(filename, "", tag.line)[tag.line]
end

local function tag_target_yaml_key(tag, tagfile)
  local line = tag_target_line(tag, tagfile)
  if not line then return nil end
  return line:match("^%s*([%w_][%w_-]*):")
end

local function tag_reference_names(name, tag, tagfile) return unique_names({ name, tag_target_yaml_key(tag, tagfile) }) end

local function tag_references_pattern(names)
  local escaped_names = vim.tbl_map(rg_escape, names)
  if #escaped_names == 1 then return "\\b" .. escaped_names[1] .. "\\b" end
  return "\\b(?:" .. table.concat(escaped_names, "|") .. ")\\b"
end

local function is_reference_item(item) return not item.text:match("#%s*ctags%-link:") end

local function resolve_tag(name)
  local tagfile = tags_file()
  if not tagfile then
    vim.api.nvim_echo({ { "No tags file found", "DiagnosticWarn" } }, false, {})
    return nil
  end

  local tags = {}
  for _, line in ipairs(vim.fn.readfile(tagfile)) do
    local tag = parse_tag_line(line, name)
    if tag then table.insert(tags, tag) end
  end

  if not vim.tbl_isempty(tags) then return select_tag(tags, tagfile), tagfile end

  vim.fn.setqflist({}, " ", {
    context = { name = "user.ctags.references", tag = name, tag_resolved = false },
    items = {},
    title = ("[Tag references] no ctags entry: %s"):format(name),
  })
  vim.api.nvim_echo({ { ("No ctags entry for: %s"):format(name), "DiagnosticWarn" } }, false, {})
  return nil
end

local function tag_references(command_args)
  local name = command_args and command_args.args ~= "" and command_args.args or tag_name_under_cursor()
  if not name then return end
  local tag, tagfile = resolve_tag(name)
  if not tag then return end
  local reference_names = tag_reference_names(name, tag, tagfile)
  local pattern = tag_references_pattern(reference_names)

  if active_tag_references then active_tag_references.cancel() end

  active_tag_references = utils.grep_with_rg_to_qflist(rg_search_arg(pattern), {
    context = { name = "user.ctags.references", reference_names = reference_names, tag = tag },
    on_finish = function(count)
      active_tag_references = nil
      if count > 0 then pcall(vim.cmd.copen) end
    end,
    qf_item_filter = is_reference_item,
    rg_args = { "--glob", "!tags" },
    search_paths = { utils.git_root_or_cwd() },
    title_prefix = "Tag references",
  })
end

vim.api.nvim_create_user_command("TagReferences", tag_references, {
  force = true,
  nargs = "?",
  desc = "Find references to the tag under cursor",
})

vim.keymap.set("n", "<leader>cr", tag_references, { desc = "Find ctags references" })
