vim.loader.enable()

vim.filetype.add({
  filename = {
    ["sxhkdrc"] = "sxhkdrc",
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "sh",
    ["dot-gitconfig"] = "gitconfig",
    ["xhtml"] = "html",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["%.env.*"] = "sh",
    [".*/udev%-rules/.*%.rules"] = "udevrules",
  },
})

require("serranomorante")
