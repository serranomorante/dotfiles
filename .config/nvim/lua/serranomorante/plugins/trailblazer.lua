return {
  "LeonHeidelbach/trailblazer.nvim",
  event = "User CustomFile",
  keys = {
    {
      "<A-l>",
      function() require("trailblazer").new_trail_mark() end,
      desc = "Trailblazer: Create a new / toggle existing trail mark",
      mode = { "n", "v" },
    },
    {
      "<A-b>",
      function() require("trailblazer").track_back() end,
      desc = "Trailblazer: Move to the last global trail mark and remove it from the trail mark stack",
      mode = { "n", "v" },
    },
    {
      "<A-J>",
      function()
        local ok, result = pcall(require("trailblazer").peek_move_next_down)
        if not ok and string.find(result, "common.lua:3") then return vim.notify("Marks empty", vim.log.levels.WARN) end
        if not ok then vim.notify(string.format("Error: %s", result), vim.log.levels.ERROR) end
      end,
      desc = "Trailblazer: Move to the next global trail mark",
      mode = { "n", "v" },
    },
    {
      "<A-K>",
      function()
        local ok, result = pcall(require("trailblazer").peek_move_previous_up)
        if not ok and string.find(result, "common.lua:3") then return vim.notify("Marks empty", vim.log.levels.WARN) end
        if not ok then vim.notify(string.format("Error: %s", result), vim.log.levels.ERROR) end
      end,
      desc = "Trailblazer: Move to the previous global trail mark",
      mode = { "n", "v" },
    },
    {
      "<A-m>",
      function() require("trailblazer").toggle_trail_mark_list() end,
      desc = "Trailblazer: Toggle a global list of all trail marks",
      mode = { "n", "v" },
    },
    {
      "<A-S>",
      function() require("trailblazer").delete_all_trail_marks() end,
      desc = "Trailblazer: Delete all trail marks globally",
      mode = { "n", "v" },
    },
    {
      "<A-.>",
      function() require("trailblazer").switch_to_next_trail_mark_stack() end,
      desc = "Trailblazer: Switch to the next trail mark stack",
      mode = { "n", "v" },
    },
    {
      "<A-,>",
      function() require("trailblazer").switch_to_previous_trail_mark_stack() end,
      desc = "Trailblazer: Switch to the previous trail mark stack",
      mode = { "n", "v" },
    },
    {
      "<A-M>",
      function()
        vim.ui.input(
          { prompt = "Stack Name: " },
          function(input) require("trailblazer").switch_trail_mark_stack(input, false) end
        )
      end,
      desc = "Trailblazer: Add new trail mark stack",
    },
  },
  opts = function()
    local opts = {
      auto_save_trailblazer_state_on_exit = false, -- we are manually doing it on `persistence.nvim`
      auto_load_trailblazer_state_on_enter = false, -- we are manually doing it on `persistence.nvim`
      trail_options = {
        ---Marks are sorted by their buffer id and globally traversed from BOF to EOF
        current_trail_mark_mode = "global_buf_line_sorted",
        available_trail_mark_modes = { "global_buf_line_sorted" },
        mark_symbol = "",
        newest_mark_symbol = "",
        cursor_mark_symbol = "",
        next_mark_symbol = "",
        previous_mark_symbol = "",
        trail_mark_priority = 20, -- nvim-dap breakpoints priority is 21
        multiple_mark_symbol_counters_enabled = false,
        number_line_color_enabled = false,
        trail_mark_in_text_highlights_enabled = false,
        trail_mark_symbol_line_indicators_enabled = true,
        move_to_nearest_before_peek = true,
      },
      force_mappings = {},
      force_quickfix_mappings = {
        nv = {
          actions = {
            qf_action_delete_trail_mark_selection = "d",
            qf_action_save_visual_selection_start_line = "v",
          },
          alt_actions = {
            qf_action_save_visual_selection_start_line = "V",
          },
        },
        v = {
          actions = {
            qf_action_move_selected_trail_marks_down = "<C-j>",
            qf_action_move_selected_trail_marks_up = "<C-k>",
          },
        },
      },
    }

    local hl_groups = {
      TrailBlazerTrailMark = { link = "Constant" },
      TrailBlazerTrailMarkNext = { link = "Constant" },
      TrailBlazerTrailMarkPrevious = { link = "Constant" },
      TrailBlazerTrailMarkNewest = { link = "Constant" },
    }
    opts.hl_groups = hl_groups

    return opts
  end,
  config = function(_, opts)
    local trailblazer = require("trailblazer")
    trailblazer.setup(opts)
    ---Patch trailblazer before loading session
    ---https://github.com/LeonHeidelbach/trailblazer.nvim/discussions/51#discussioncomment-8108342
    local trailblazer_common = require("trailblazer.trails.common")
    local focus_win_and_buf = trailblazer_common.focus_win_and_buf
    trailblazer_common.focus_win_and_buf = function() return true end
    vim.schedule(function()
      ---Load session
      trailblazer.load_trailblazer_state_from_file()
      ---Unpatch trailblazer
      trailblazer_common.focus_win_and_buf = focus_win_and_buf
    end)

    vim.api.nvim_create_autocmd("VimLeavePre", {
      desc = "Save a dir-specific session when you close Neovim",
      group = vim.api.nvim_create_augroup("trailblazer_autosave_session", { clear = true }),
      callback = function()
        ---Only save the session if nvim was started with no args
        if vim.fn.argc(-1) == 0 then trailblazer.save_trailblazer_state_to_file() end
      end,
    })
  end,
}
