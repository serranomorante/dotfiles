local markdown_block_ids = require("serranomorante.markdown_block_ids")

vim.api.nvim_create_user_command("GoToFoamBlockById", function(opts)
  markdown_block_ids.goto_block_id(opts.args)
end, { force = true, nargs = 1, desc = "Go to a Foam Markdown block by @id" })
