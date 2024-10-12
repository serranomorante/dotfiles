local utils = require("serranomorante.utils")

local M = {}

local group = vim.api.nvim_create_augroup("trailblazer_autosave_session", { clear = true })

local function keys()
  vim.keymap.set(
    { "n", "v" },
    "<A-l>",
    function() require("trailblazer").new_trail_mark() end,
    { desc = "Trailblazer: toggle trail mark" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-b>",
    function() require("trailblazer").track_back() end,
    { desc = "Trailblazer: Move to the last global trail mark and remove it from the trail mark stack" }
  )

  vim.keymap.set({ "n", "v" }, "<A-j>", function()
    local ok, result = pcall(require("trailblazer").peek_move_next_down)
    if not ok and string.find(result, "common.lua:3") then return vim.notify("Marks empty", vim.log.levels.WARN) end
    if not ok then vim.notify(string.format("Error: %s", result), vim.log.levels.ERROR) end
  end, { desc = "Trailblazer: Move to the next global trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-k>", function()
    local ok, result = pcall(require("trailblazer").peek_move_previous_up)
    if not ok and string.find(result, "common.lua:3") then return vim.notify("Marks empty", vim.log.levels.WARN) end
    if not ok then vim.notify(string.format("Error: %s", result), vim.log.levels.ERROR) end
  end, { desc = "Trailblazer: Move to the previous global trail mark" })

  vim.keymap.set(
    { "n", "v" },
    "<A-m>",
    function() require("trailblazer").toggle_trail_mark_list() end,
    { desc = "Trailblazer: Toggle a global list of all trail marks" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-S>",
    function() require("trailblazer").delete_all_trail_marks() end,
    { desc = "Trailblazer: Delete all trail marks globally" }
  )

  vim.keymap.set({ "n", "v" }, "<A-.>", function()
    require("trailblazer").switch_to_next_trail_mark_stack()
    vim.schedule(vim.cmd.redrawstatus) -- TODO: move this to heirline
  end, { desc = "Trailblazer: Switch to the next trail mark stack" })

  vim.keymap.set({ "n", "v" }, "<A-,>", function()
    require("trailblazer").switch_to_previous_trail_mark_stack()
    vim.schedule(vim.cmd.redrawstatus) -- TODO: move this to heirline
  end, { desc = "Trailblazer: Switch to the previous trail mark stack" })

  vim.keymap.set("n", "<A-`>", function()
    vim.ui.input({ prompt = "Stack Name: " }, function(input)
      if not input then return end
      require("trailblazer").switch_trail_mark_stack(input, false)
      require("trailblazer").new_trail_mark()
      utils.cmd({ "notify-send", input, "--icon=bookmarks" })
    end)
  end, { desc = "Trailblazer: Add new trail mark stack" })

  vim.keymap.set("n", "<A-'>", function()
    local stacks = require("trailblazer.trails").stacks.get_sorted_stack_names()
    local current_stack = require("trailblazer.trails").stacks.current_trail_mark_stack_name
    table.remove(stacks, vim.fn.index(stacks, current_stack) + 1)
    vim.ui.select(stacks, { prompt = current_stack .. " " }, function(choice)
      if choice then require("trailblazer").switch_trail_mark_stack(choice) end
    end)
  end, { desc = "Trailblazer: Switch stack" })
end

local function opts()
  return {
    auto_save_trailblazer_state_on_exit = false,
    auto_load_trailblazer_state_on_enter = false,
    trail_options = {
      current_trail_mark_stack_sort_mode = "chron_asc",
      mark_symbol = "",
      newest_mark_symbol = "",
      cursor_mark_symbol = "",
      next_mark_symbol = "",
      previous_mark_symbol = "",
      trail_mark_priority = 20, -- nvim-dap breakpoints priority is 21
      multiple_mark_symbol_counters_enabled = false,
      number_line_color_enabled = false,
      trail_mark_in_text_highlights_enabled = false,
      trail_mark_symbol_line_indicators_enabled = true,
    },
    force_mappings = {},
    force_quickfix_mappings = {
      nv = {
        motions = {
          qf_motion_move_trail_mark_stack_cursor = "<CR>",
        },
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
end

function M.config()
  keys()
  local trailblazer = require("trailblazer")
  trailblazer.setup(opts())
  vim.schedule(trailblazer.load_trailblazer_state_from_file)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Save a dir-specific session when you close Neovim",
    group = group,
    callback = function()
      ---Only save the session if nvim was started with no args
      if vim.fn.argc(-1) == 0 then trailblazer.save_trailblazer_state_to_file() end
    end,
  })
end

return M