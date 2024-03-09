return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "kevinhwang91/nvim-treesitter",
    ---Test adapters
    "marilari88/neotest-vitest",
    "nvim-neotest/neotest-python",
    "nvim-neotest/neotest-plenary",
  },
  ---https://github.com/rcarriga/dotfiles/blob/8bf909cc6ee323134b4225f762fa381a47986d15/.config/nvim/lua/config/neotest.lua
  keys = {
    {
      "<leader>nr",
      function() require("neotest").run.run({ vim.fn.expand("%:p") }) end,
      desc = "Neotest: Run the current file",
    },
    {
      "<leader>ns",
      function()
        local neotest = require("neotest")
        for _, adapter_id in ipairs(neotest.state.adapter_ids()) do
          neotest.run.run({ suite = true, adapter = adapter_id })
        end
      end,
      desc = "Neotest: Run the entire suite across adapters",
    },
    {
      "<leader>nx",
      function() require("neotest").run.stop() end,
      desc = "Neotest: Stop a running process",
    },
    {
      "<leader>nn",
      function() require("neotest").run.run() end,
      desc = "Neotest: Run the nearest test",
    },
    {
      "<leader>nl",
      function() require("neotest").run.run_last() end,
      desc = "Neotest: Run the last position that was run with the same arguments",
    },
    {
      "<leader>nd",
      function() require("neotest").run.run({ strategy = "dap" }) end,
      desc = "Neotest: Debug the nearest test with nvim-dap",
    },
    {
      "<leader>na",
      function() require("neotest").run.attach() end,
      desc = "Neotest: Attach to a running process for the given position.",
    },
    {
      "<leader>no",
      function() require("neotest").output.open({ enter = true, last_run = true }) end,
      desc = "Neotest: Open output for last test run",
    },
    {
      "<leader>ni",
      function() require("neotest").output.open({ enter = true }) end,
      desc = "Neotest: Open the output of a test result",
    },
    {
      "<leader>nO",
      function() require("neotest").output.open({ enter = true, short = true }) end,
      desc = "Neotest: Show shortened output",
    },
    {
      "<leader>np",
      function() require("neotest").summary.toggle() end,
      desc = "Neotest: Toggle the summary window",
    },
    {
      "<leader>nm",
      function() require("neotest").summary.run_marked() end,
      desc = "Neotest: Run all marked positions",
    },
    {
      "<leader>ne",
      function() require("neotest").output_panel.toggle() end,
      desc = "Neotest: Toggle the output panel",
    },
    {
      "[n",
      function() require("neotest").jump.prev({ status = "failed" }) end,
      desc = "Neotest: Jump to prev failed test",
    },
    {
      "]n",
      function() require("neotest").jump.next({ status = "failed" }) end,
      desc = "Neotest: Jump to next failed test",
    },
  },
  opts = function()
    return {
      log_level = vim.log.levels[vim.env.NEOTEST_LOG_LEVEL or "INFO"],
      quickfix = {
        open = false,
      },
      status = {
        virtual_text = true,
        signs = true,
      },
      output = {
        open_on_run = false,
      },
      icons = {
        running_animated = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      },
      strategies = {
        integrated = {
          width = 180,
        },
      },
      floating = {
        border = "single",
      },
      adapters = {
        require("neotest-vitest"),
        require("neotest-python"),
        require("neotest-plenary"),
      },
    }
  end,
  init = function()
    local group = vim.api.nvim_create_augroup("NeotestConfig", {})
    for _, ft in ipairs({ "output", "attach", "summary" }) do
      vim.api.nvim_create_autocmd("FileType", {
        desc = "Close neotest windows",
        pattern = "neotest-" .. ft,
        group = group,
        callback = function(opts)
          vim.keymap.set("n", "q", function() pcall(vim.api.nvim_win_close, 0, true) end, {
            buffer = opts.buf,
          })
        end,
      })
    end

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "neotest-output-panel",
      group = group,
      callback = function() vim.cmd("norm G") end,
    })
  end,
}
