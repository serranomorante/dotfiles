vim.loader.enable()

local ui2_available, ui2 = pcall(require, "vim._core.ui2")
if ui2_available then ui2.enable({
  msg = {
    targets = "msg",
    msg = {
      timeout = 4000,
    },
  },
}) end

vim.filetype.add({
  filename = {
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "sh",
    ["dot-gitconfig"] = "gitconfig",
    ["xhtml"] = "html",
    ["dap.log"] = "sh",
    ["conform.log"] = "gitconfig",
    ["tox.ini"] = "gitconfig",
    ["kitty.conf"] = "kitty",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["%.env.*"] = "sh",
    [".*%.cfg"] = "gitconfig",
    [".*%.code%-workspace"] = "json",
    [".*%.service"] = "systemd",
    [".*%.desktop"] = "gitconfig",
    [".*/udev%-rules/.*%.rules"] = "udevrules",
    [".*/keyd/.*%.conf"] = "gitignore",
    [".*keyd.*%.conf"] = "gitignore",
    [".*%.inc"] = "gitignore",
  },
})

require("serranomorante")
