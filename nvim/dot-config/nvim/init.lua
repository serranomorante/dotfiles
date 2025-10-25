vim.loader.enable()
require("vim._extui").enable({})

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
    [".*%.service"] = "systemd",
    [".*%.desktop"] = "gitconfig",
    [".*/udev%-rules/.*%.rules"] = "udevrules",
    [".*/keyd/.*%.conf"] = "gitignore",
    [".*keyd.*%.conf"] = "gitignore",
  },
})

require("serranomorante")
