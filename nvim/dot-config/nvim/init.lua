vim.loader.enable()

vim.filetype.add({
  filename = {
    ["sxhkdrc"] = "sxhkdrc",
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "bash",
    ["xhtml"] = "html",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["^%.env.*"] = "bash",
  },
})

require("serranomorante")
