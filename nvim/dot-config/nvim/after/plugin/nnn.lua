local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")

---Writes a Grep/Find command into vim's command-line with
---nnn's hovered dir prepopulated
---@param command_args vim.api.keyset.create_user_command.command_args
local function nnn_search_in_dir(command_args)
  local search_type, filepath = unpack(command_args.fargs)
  local search_dir = vim.fn.fnamemodify(filepath or "", ":p:~:h")
  if not utils.is_directory(vim.fn.expand(search_dir)) then
    local msg = '[NNN] %s search aborted. Directory "%s" not found'
    return vim.api.nvim_echo({ { msg:format(search_type, search_dir) } }, false, { err = true })
  end
  if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "terminal" then vim.api.nvim_win_close(0, true) end
  utils.feedkeys(string.format(":%s '' %s", search_type, search_dir), "n")
  utils.feedkeys(constants.POSITION_CURSOR_BETWEEN_QUOTES, "n")
end

vim.api.nvim_create_user_command("NNNSearch", nnn_search_in_dir, {
  force = true,
  nargs = "*",
})
