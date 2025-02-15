vim.api.nvim_create_user_command("Grep", "silent grep -e <args>", { force = true, nargs = "?" })
