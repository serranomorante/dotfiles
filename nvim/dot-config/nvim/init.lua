vim.loader.enable()

vim.filetype.add({
  filename = {
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "sh",
    ["dot-gitconfig"] = "gitconfig",
    ["xhtml"] = "html",
    ["dap.log"] = "sh",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["%.env.*"] = "sh",
    [".*/udev%-rules/.*%.rules"] = "udevrules",
    [".*/keyd/.*%.conf"] = "gitignore",
    [".*keyd.*%.conf"] = "gitignore",
  },
})

require("serranomorante")
