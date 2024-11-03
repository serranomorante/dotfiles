vim.loader.enable()

vim.filetype.add({
  filename = {
    ["sxhkdrc"] = "sxhkdrc",
    [".stow-global-ignore"] = "gitignore",
    [".stow-local-ignore"] = "gitignore",
    ["dot-bashrc"] = "sh",
    ["xhtml"] = "html",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
    ["%.env.*"] = "sh",
    [".*%.service"] = "gitconfig",
    [".*%.timer"] = "gitconfig",
    [".*/pipewire/.*/.*%.conf"] = "gitconfig",
    [".*/wireplumber/.*/.*%.conf"] = "gitconfig",
    [".*/keyd/.*%.conf"] = "gitconfig",
  },
})

require("serranomorante")
