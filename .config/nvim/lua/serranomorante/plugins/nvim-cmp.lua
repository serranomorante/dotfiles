local utils = require("serranomorante.utils")

return {
  {
    "L3MON4D3/LuaSnip",
    lazy = true,
    build = vim.fn.has("win32") == 0
        and "echo 'NOTE: jsregexp is optional, so not a big deal if it fails to build\n'; make install_jsregexp"
      or nil,
    opts = {
      -- Don't jump into snippets that have been left
      -- Thanks: https://github.com/AstroNvim/AstroNvim/commit/af54d1481ee217a2389230109cbd298f24639118
      history = true,
      delete_check_events = "TextChanged",
      region_check_events = "CursorMoved",
    },
    config = function(_, opts)
      if opts then require("luasnip").config.setup(opts) end
      require("luasnip.loaders.from_lua").lazy_load({
        ---@diagnostic disable-next-line: param-type-mismatch
        paths = { utils.join_paths(vim.fn.stdpath("config"), "lua/serranomorante/snippets") },
      })
    end,
  },

  { "rcarriga/cmp-dap", lazy = true },

  {
    "hrsh7th/nvim-cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      "saadparwaiz1/cmp_luasnip",
      "onsails/lspkind.nvim",
      "hrsh7th/cmp-nvim-lsp-signature-help",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-buffer",
    },
    init = function()
      vim.opt.completeopt = { "menu", "menuone", "noselect" } -- Options for insert mode completion

      ---https://github.com/hrsh7th/cmp-cmdline/issues/94
      vim.api.nvim_create_autocmd("CmdWinEnter", {
        desc = "Close completion menu when entering cmdwin",
        group = vim.api.nvim_create_augroup("cmdwin_close_completion", { clear = true }),
        callback = function() require("cmp").close() end,
      })
    end,
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      local lspkind = require("lspkind")
      lspkind.init({})

      local border_opts = {
        border = "single",
        winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel,Search:None",
      }

      -- https://github.com/zbirenbaum/copilot-cmp#tab-completion-configuration-highly-recommended
      local has_words_before = function()
        if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt" then return false end
        local line, col = (unpack or table.unpack)(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
      end

      cmp.setup({
        enabled = function()
          local buf = vim.api.nvim_get_current_buf()
          local dap_prompt = utils.is_available("cmp-dap") -- add interoperability with cmp-dap
            and vim.tbl_contains({ "dap-repl" }, vim.api.nvim_get_option_value("filetype", { buf = buf }))

          ---Disable for any prompts other than nvim-dap
          if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "prompt" and not dap_prompt then
            return false
          end

          ---Disable for very large files
          if vim.b[buf].large_buf then return false end
          return true
        end,
        snippet = { -- configure how nvim-cmp interacts with snippet engine
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        sources = cmp.config.sources({
          { name = "luasnip" },
          {
            name = "nvim_lsp",
            entry_filter = function(entry, _)
              return require("cmp.types").lsp.CompletionItemKind[entry:get_kind()] ~= "Text"
            end,
          },
          { name = "nvim_lsp_signature_help" },
          { name = "buffer" },
          { name = "path" },
        }),
        mapping = {
          ["<Up>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
          ["<Down>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
          ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-k>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-j>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
          ["<C-u>"] = cmp.mapping(cmp.mapping.scroll_docs(-4), { "i", "c" }),
          ["<C-d>"] = cmp.mapping(cmp.mapping.scroll_docs(4), { "i", "c" }),
          ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), { "i", "c" }),
          ["<C-y>"] = cmp.config.disable,
          ["<C-e>"] = cmp.mapping({ i = cmp.mapping.abort(), c = cmp.mapping.close() }),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        },
        window = {
          completion = cmp.config.window.bordered(border_opts),
          documentation = cmp.config.window.bordered(border_opts),
        },
        formatting = {
          format = lspkind.cmp_format({
            mode = "symbol_text",
            menu = {
              buffer = "[buf]",
              nvim_lsp = "[LSP]",
              path = "[path]",
              luasnip = "[snip]",
            },
          }),
        },
        preselect = cmp.PreselectMode.None,
        performance = {
          max_view_entries = 7,
        },
      })

      cmp.setup.filetype("gitcommit", {
        sources = {
          { name = "path" },
          { name = "buffer" },
        },
      })

      -- `/` cmdline setup.
      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      -- `:` cmdline setup.
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
      })
    end,
  },
}
