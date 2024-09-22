vim.loader.enable()

vim.filetype.add({
  filename = {
    ["sxhkdrc"] = "sxhkdrc",
  },
  pattern = {
    [".*/requirements.*%.txt"] = "requirements",
  },
})

require("serranomorante")
