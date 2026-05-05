local M = {}

local ns = vim.api.nvim_create_namespace("serranomorante.markdown_images")

local defaults = {
  max_width = 80,
  max_height = 24,
  min_width = 12,
  zindex = 50,
}

---@class MarkdownImagePreview
---@field bufnr integer
---@field enabled boolean
---@field ids integer[]
---@field augroup integer?
---@field timer uv.uv_timer_t?
---@field notify_missing_api boolean?
---@field notify_render_error boolean?

---@type table<integer, MarkdownImagePreview>
local buffers = {}

---@type table<string, {stamp:string, bytes:string, width:integer, height:integer}>
local image_cache = {}

---@type boolean?
local terminal_supports_images

---@param msg string
---@param level integer
local function notify(msg, level) vim.notify(msg, level, { title = "markdown images" }) end

---@param bufnr integer?
---@return integer
local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then return vim.api.nvim_get_current_buf() end
  return bufnr
end

---@return boolean
local function img_api_available()
  if type(vim.ui) ~= "table" or type(vim.ui.img) ~= "table" or type(vim.ui.img.set) ~= "function" then return false end

  if terminal_supports_images ~= nil then return terminal_supports_images end

  if type(vim.ui.img._supported) ~= "function" then
    terminal_supports_images = true
    return true
  end

  local ok, supported = pcall(vim.ui.img._supported, { timeout = 100 })
  terminal_supports_images = ok and supported
  return terminal_supports_images
end

---@param bytes string
---@return integer?
---@return integer?
local function png_dimensions(bytes)
  if bytes:sub(1, 8) ~= "\137PNG\r\n\026\n" or bytes:sub(13, 16) ~= "IHDR" then return nil, nil end

  local w1, w2, w3, w4 = bytes:byte(17, 20)
  local h1, h2, h3, h4 = bytes:byte(21, 24)
  if not w1 or not h1 then return nil, nil end

  local width = ((w1 * 256 + w2) * 256 + w3) * 256 + w4
  local height = ((h1 * 256 + h2) * 256 + h3) * 256 + h4
  return width, height
end

---@param path string
---@return {bytes:string, width:integer, height:integer}?
local function load_png(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then return nil end

  local stamp = ("%d:%d:%d"):format(stat.size or 0, stat.mtime.sec or 0, stat.mtime.nsec or 0)
  local cached = image_cache[path]
  if cached and cached.stamp == stamp then return cached end

  local ok, bytes = pcall(vim.fn.readblob, path)
  if not ok or type(bytes) ~= "string" then return nil end

  local width, height = png_dimensions(bytes)
  if not width or not height then return nil end

  local entry = { stamp = stamp, bytes = bytes, width = width, height = height }
  image_cache[path] = entry
  return entry
end

---@param path string
---@param bufnr integer
---@return string?
local function resolve_path(path, bufnr)
  path = vim.trim(path)
  if path == "" then return nil end

  local angle_path = path:match("^<(.+)>")
  if angle_path then
    path = angle_path
  else
    path = path:match("^([^%s]+)") or ""
  end

  path = path:gsub("\\ ", " ")

  if path:match("^%a[%w+.-]*:") then
    if vim.startswith(path, "file://") then return vim.uri_to_fname(path) end
    return nil
  end

  if vim.uri_decode and path:find("%%") then path = vim.uri_decode(path) end

  if vim.startswith(path, "~") then return vim.fn.fnamemodify(vim.fn.expand(path), ":p") end
  if vim.startswith(path, "/") then return vim.fn.fnamemodify(path, ":p") end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local base = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()
  return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

---@param width integer
---@param height integer
---@param available_width integer?
---@return {width:integer, height:integer}
local function display_size(width, height, available_width)
  local cell_width = math.min(defaults.max_width, available_width or defaults.max_width)
  cell_width = math.max(defaults.min_width, math.min(cell_width, width))

  local cell_height = math.ceil((height / width) * cell_width * 0.5)
  cell_height = math.max(1, math.min(defaults.max_height, cell_height))

  return { width = cell_width, height = cell_height }
end

---@param height integer
---@return table
local function blank_virt_lines(height)
  local lines = {}
  for _ = 1, height do
    table.insert(lines, { { " ", "Normal" } })
  end
  return lines
end

---@param bufnr integer
---@return {lnum:integer, path:string, image:{bytes:string, width:integer, height:integer}, size:{width:integer, height:integer}}[]
local function find_images(bufnr)
  local items = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    local raw_path = line:match("!%[[^%]]*%]%(([^%)]+)%)")
    if raw_path then
      local path = resolve_path(raw_path, bufnr)
      local image = path and load_png(path)
      if image then
        local size = display_size(image.width, image.height)
        table.insert(items, {
          lnum = i,
          path = path,
          image = image,
          size = size,
        })
      end
    end
  end

  return items
end

---@param bufnr integer
local function clear_images(bufnr)
  local state = buffers[bufnr]
  if state then
    for _, id in ipairs(state.ids) do
      pcall(vim.ui.img.del, id)
    end
    state.ids = {}
  end

  if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1) end
end

---@param winid integer
---@return integer
---@return integer
local function visible_lines(winid)
  return unpack(vim.api.nvim_win_call(winid, function() return { vim.fn.line("w0"), vim.fn.line("w$") } end))
end

---@param bufnr integer
function M.render(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr]
  if not state or not state.enabled or not vim.api.nvim_buf_is_valid(bufnr) then return end

  clear_images(bufnr)

  if not img_api_available() then
    if vim.g.markdown_images_notify_unsupported and not state.notify_missing_api then
      notify("vim.ui.img is unavailable or unsupported in this terminal", vim.log.levels.WARN)
      state.notify_missing_api = true
    end
    return
  end

  local items = find_images(bufnr)
  if #items == 0 then return end

  for _, item in ipairs(items) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, item.lnum - 1, 0, {
      virt_lines = blank_virt_lines(item.size.height),
      virt_lines_above = false,
      virt_lines_leftcol = false,
    })
  end

  vim.cmd.redraw()

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      local topline, botline = visible_lines(winid)
      local win_width = vim.api.nvim_win_get_width(winid)

      for _, item in ipairs(items) do
        if item.lnum >= topline and item.lnum <= botline then
          local pos = vim.fn.screenpos(winid, item.lnum, 1)
          if pos.row and pos.row > 0 and pos.col and pos.col > 0 then
            local available_width = math.max(defaults.min_width, win_width - pos.col)
            local size = display_size(item.image.width, item.image.height, available_width)
            local ok, id = pcall(vim.ui.img.set, item.image.bytes, {
              row = pos.row + 1,
              col = pos.col,
              width = size.width,
              height = size.height,
              zindex = defaults.zindex,
            })

            if ok then
              table.insert(state.ids, id)
            elseif not state.notify_render_error then
              notify(("failed to render %s: %s"):format(item.path, id), vim.log.levels.ERROR)
              state.notify_render_error = true
            end
          end
        end
      end
    end
  end
end

---@param bufnr integer
function M.schedule(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr]
  if not state or not state.enabled then return end

  if state.timer then
    state.timer:stop()
    state.timer:close()
  end

  state.timer = vim.uv.new_timer()
  if not state.timer then
    vim.schedule(function() M.render(bufnr) end)
    return
  end

  state.timer:start(60, 0, function()
    vim.schedule(function()
      if state.timer then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
      end
      M.render(bufnr)
    end)
  end)
end

---@param bufnr integer
function M.enable(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr] or { bufnr = bufnr, enabled = false, ids = {} }
  buffers[bufnr] = state
  state.enabled = true

  if state.augroup then pcall(vim.api.nvim_del_augroup_by_id, state.augroup) end

  state.augroup = vim.api.nvim_create_augroup(("serranomorante_markdown_images_%d"):format(bufnr), { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = state.augroup,
    buffer = bufnr,
    callback = function(args) M.schedule(args.buf) end,
  })

  vim.api.nvim_create_autocmd({ "WinScrolled", "WinEnter", "VimResized" }, {
    group = state.augroup,
    callback = function()
      if buffers[bufnr] and vim.api.nvim_buf_is_valid(bufnr) then M.schedule(bufnr) end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete" }, {
    group = state.augroup,
    buffer = bufnr,
    callback = function(args) M.disable(args.buf) end,
  })

  M.schedule(bufnr)
end

---@param bufnr integer
function M.disable(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr]
  if not state then return end

  state.enabled = false

  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  clear_images(bufnr)

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
end

---@param bufnr integer
function M.toggle(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr]
  if state and state.enabled then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

---@param bufnr integer
function M.attach(bufnr)
  bufnr = normalize_bufnr(bufnr)

  vim.api.nvim_buf_create_user_command(bufnr, "MarkdownImagesRefresh", function() M.render(bufnr) end, {
    force = true,
    desc = "Refresh inline markdown image previews",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "MarkdownImagesEnable", function() M.enable(bufnr) end, {
    force = true,
    desc = "Enable inline markdown image previews",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "MarkdownImagesDisable", function() M.disable(bufnr) end, {
    force = true,
    desc = "Disable inline markdown image previews",
  })

  vim.api.nvim_buf_create_user_command(bufnr, "MarkdownImagesToggle", function() M.toggle(bufnr) end, {
    force = true,
    desc = "Toggle inline markdown image previews",
  })

  vim.keymap.set("n", "<leader>mi", function() M.toggle(bufnr) end, {
    buffer = bufnr,
    desc = "Markdown: toggle inline image previews",
  })
end

return M
