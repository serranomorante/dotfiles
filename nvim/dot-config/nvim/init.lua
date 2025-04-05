vim.loader.enable()

vim.filetype.add({
  filename = {
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "sh",
    ["dot-gitconfig"] = "gitconfig",
    ["xhtml"] = "html",
    ["dap.log"] = "sh",
    ["tox.ini"] = "gitconfig",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["%.env.*"] = "sh",
    [".*%.service"] = "systemd",
    [".*/udev%-rules/.*%.rules"] = "udevrules",
    [".*/keyd/.*%.conf"] = "gitignore",
    [".*keyd.*%.conf"] = "gitignore",
  },
})

require("serranomorante")
