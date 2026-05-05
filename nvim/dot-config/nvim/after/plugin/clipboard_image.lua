local utils = require("serranomorante.utils")

local function run_save_clipboard_image(image_dir)
  local output = vim.fn.system({ "save-clipboard-image", image_dir })
  local ok = vim.v.shell_error == 0
  return ok, vim.fn.trim(output)
end

local function paste_clipboard_image()
  local bufnr = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if buftype ~= "" or not modifiable then
    vim.api.nvim_echo({ { "Cannot paste clipboard image into this buffer", "DiagnosticWarn" } }, false, {})
    return
  end

  if vim.fn.executable("save-clipboard-image") ~= 1 then
    vim.api.nvim_echo({ { "save-clipboard-image is not executable", "DiagnosticError" } }, false, {})
    return
  end

  local image_dir = utils.join_paths(vim.fn.getcwd(), "assets", "images")
  local ok, output = run_save_clipboard_image(image_dir)
  if not ok then
    if output == "" then
      vim.api.nvim_echo({ { "No image found in clipboard", "DiagnosticWarn" } }, false, {})
    else
      vim.api.nvim_echo({ { output, "DiagnosticError" } }, false, {})
    end
    return
  end

  local image_path = output
  if image_path == "" then
    vim.api.nvim_echo({ { "save-clipboard-image did not return a path", "DiagnosticError" } }, false, {})
    return
  end

  local filename = vim.fn.fnamemodify(image_path, ":t")
  vim.api.nvim_put({ string.format("![%s](%s)", filename, image_path) }, "c", true, true)
end

vim.api.nvim_create_user_command("PasteClipboardImage", paste_clipboard_image, {
  force = true,
  desc = "Save clipboard image to assets/images and insert markdown link",
})
