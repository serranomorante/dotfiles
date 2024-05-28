---Thanks!
---https://github.com/stevearc/resession.nvim/blob/master/lua/resession/files.lua

M = {}

---@param filepath string
---@return boolean
M.exists = function(filepath)
  local stat = vim.uv.fs_stat(filepath)
  return stat ~= nil and stat.type ~= nil
end

---@param filename string
---@param contents string
M.write_file = function(filename, contents)
  local fd = assert(vim.uv.fs_open(filename, "w", 420))
  vim.uv.fs_write(fd, contents)
  vim.uv.fs_close(fd)
end

---@param filepath string
---@return string?
M.read_file = function(filepath)
  if not M.exists(filepath) then return nil end
  local fd = assert(vim.uv.fs_open(filepath, "r", 420)) -- 0644
  local stat = assert(vim.uv.fs_fstat(fd))
  local content = vim.uv.fs_read(fd, stat.size)
  vim.uv.fs_close(fd)
  return content
end

---@param filename string
---@param obj any
M.write_json_file = function(filename, obj) M.write_file(filename .. ".json", vim.json.encode(obj)) end

---@param filepath string
---@return any?
M.load_json_file = function(filepath)
  local content = M.read_file(filepath .. ".json")
  if content then return vim.json.decode(content, { luanil = { object = true } }) end
end

---@param filename string
---@param user_data table
M.save = function(filename, user_data)
  local data = {}
  data = vim.tbl_deep_extend("force", data, user_data)
  M.write_json_file(filename, data)
end

---Do some cleaning before saving session
---Remove buffers outside cwd, remove buffers that are directories
M.clean_before_session_save = function()
  local cwd = vim.uv.cwd()
  if cwd and cwd:sub(-1) ~= "/" then cwd = cwd .. "/" end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local delete = nil
    local bufname = vim.api.nvim_buf_get_name(buf)
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
    if vim.list_contains({ "Outline" }, filetype) then
      ---Delete buffers if filetype match
      delete = true
    elseif bufname:sub(1, #cwd) ~= cwd or vim.fn.isdirectory(bufname) == 1 then
      ---Delete buffers outside cwd
      delete = true
    elseif vim.tbl_contains({ "terminal" }, buftype) then
      ---Skip deleting terminal buffers (because it fails)
      ---they will not be persisted in the session anyways
      delete = false
    end
    if delete then vim.api.nvim_buf_delete(buf, { force = true }) end
  end
end

return M
