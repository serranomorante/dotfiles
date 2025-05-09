local utils = require("serranomorante.utils")

local M = {}

local group = vim.api.nvim_create_augroup("trailblazer-custom-config", { clear = true })

---Check if trailblazer quickfix window is open
---@param any_qf boolean? Check if any qf window is open (not only trailblazer)
local function is_trailblazer_qf_open(any_qf)
  return require("trailblazer.trails").list.get_trailblazer_quickfix_buf(any_qf)
end

local function init()
  local color = "#005869"
  vim.api.nvim_set_hl(0, "TrailblazerCustomMark", { fg = color, bg = "NONE" })
  vim.api.nvim_set_hl(0, "TrailblazerCustomMarkInvert", { fg = "NONE", bg = color })

  vim.filetype.add({
    pattern = {
      [".*%.tbsv"] = "json",
    },
  })

  vim.api.nvim_create_autocmd("FileType", {
    desc = "Add trailblazer keymaps when opening compatible qf buffer",
    group = group,
    pattern = "qf",
    callback = function()
      if is_trailblazer_qf_open() then
        local list = require("trailblazer.trails.list")
        list.register_quickfix_keybindings(list.config.quickfix_mappings)
      end
    end,
  })
end

local function echo_marks_empty() vim.api.nvim_echo({ { "Marks empty", "DiagnosticWarn" } }, false, {}) end

local function keys()
  local trailblazer = require("trailblazer")
  local trails = require("trailblazer.trails")

  vim.keymap.set({ "n", "v" }, "<A-l>", trailblazer.new_trail_mark, { desc = "Trailblazer: toggle trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-j>", function()
    if is_trailblazer_qf_open(true) and not is_trailblazer_qf_open() then return utils.next_qf_item() end
    if #trails.stacks.current_trail_mark_stack == 0 then return echo_marks_empty() end
    trailblazer.switch_trail_mark_stack(trails.stacks.current_trail_mark_stack_name, false) -- fixes trails getting stuck
    trailblazer.move_to_nearest(vim.api.nvim_get_current_buf(), "fpath_down", "lin_char_dist")
  end, { desc = "Trailblazer: Move to the next global trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-k>", function()
    if is_trailblazer_qf_open(true) and not is_trailblazer_qf_open() then return utils.prev_qf_item() end
    if #trails.stacks.current_trail_mark_stack == 0 then return echo_marks_empty() end
    trailblazer.switch_trail_mark_stack(trails.stacks.current_trail_mark_stack_name, false) -- fixes trails getting stuck
    trailblazer.move_to_nearest(vim.api.nvim_get_current_buf(), "fpath_up", "lin_char_dist")
  end, { desc = "Trailblazer: Move to the previous global trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-m>", function()
    trailblazer.toggle_trail_mark_list("quickfix")
    if is_trailblazer_qf_open() then vim.cmd.wincmd({ args = { "p" } }) end
  end, { desc = "Trailblazer: Toggle a global list of all trail marks" })

  vim.keymap.set(
    { "n", "v" },
    "<A-S>",
    trailblazer.delete_all_trail_marks,
    { desc = "Trailblazer: Delete all trail marks globally" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-.>",
    trailblazer.switch_to_next_trail_mark_stack,
    { desc = "Trailblazer: Switch to the next trail mark stack" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-,>",
    trailblazer.switch_to_previous_trail_mark_stack,
    { desc = "Trailblazer: Switch to the previous trail mark stack" }
  )

  vim.keymap.set("n", "<A-`>", function()
    vim.ui.input({ prompt = "Stack Name: " }, function(input)
      if not input then return end
      trailblazer.switch_trail_mark_stack(input, false)
      trailblazer.new_trail_mark()
      utils.cmd({ "notify-send", input, "--icon=bookmarks" })
    end)
  end, { desc = "Trailblazer: Add new trail mark stack" })

  vim.keymap.set("n", "<A-'>", function()
    local stacks = trails.stacks.trail_mark_stack_list
    local current_stack = trails.stacks.current_trail_mark_stack_name
    local stacks_names = trails.stacks.get_sorted_stack_names("alpha_asc")

    vim.ui.select(stacks_names, {
      prompt = "Choose a stack ",
      format_item = function(item)
        local fitem = item
        local count = vim.tbl_count(stacks[item] and stacks[item].stack or {})
        if item == current_stack then fitem = "-> " .. fitem end -- add icon to current stack
        fitem = string.sub(" ", #tostring(vim.fn.index(stacks_names, item) + 1), 1) .. fitem -- left align
        return count > 0 and fitem .. string.format(" (%d)", count) or fitem -- add trails count if more than zero
      end,
    }, function(choice)
      if choice then trailblazer.switch_trail_mark_stack(choice, false) end
    end)
  end, { desc = "Trailblazer: Switch stack" })

  vim.keymap.set("n", "<A-s>", function()
    local modes = trails.config.custom.available_trail_mark_modes
    local current_mode = trails.config.custom.current_trail_mark_mode
    modes = vim.tbl_filter(function(mode) return mode ~= current_mode end, modes)
    vim.ui.select(modes, { prompt = current_mode .. " " }, function(choice)
      if choice then trailblazer.set_trail_mark_select_mode(choice, false) end
    end)
  end, { desc = "Trailblazer: Select mode" })

  vim.keymap.set("n", '<A-">', function()
    local stacks = trails.stacks.get_sorted_stack_names("alpha_asc")
    local current_stack = trails.stacks.current_trail_mark_stack_name
    stacks = vim.tbl_filter(function(stack) return stack ~= current_stack end, stacks)
    vim.ui.select(stacks, { prompt = "[WARNING] Delete a stack " }, function(choice)
      if choice then trailblazer.delete_trail_mark_stack(choice) end
    end)
  end, { desc = "Trailblazer: Delete stack" })
end

local function opts()
  return {
    auto_save_trailblazer_state_on_exit = false,
    auto_load_trailblazer_state_on_enter = false,
    trail_options = {
      current_trail_mark_stack_sort_mode = "alpha_asc",
      current_trail_mark_mode = "global_buf_line_sorted",
      mark_symbol = "",
      newest_mark_symbol = "",
      cursor_mark_symbol = "",
      next_mark_symbol = "",
      previous_mark_symbol = "",
      trail_mark_priority = 20,
      multiple_mark_symbol_counters_enabled = false,
      number_line_color_enabled = false,
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
    hl_groups = {
      TrailBlazerTrailMark = {
        link = "TrailblazerCustomMark",
      },
      TrailBlazerTrailMarkNext = {
        link = "TrailblazerCustomMark",
      },
      TrailBlazerTrailMarkPrevious = {
        link = "TrailblazerCustomMark",
      },
      TrailBlazerTrailMarkCursor = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkNewest = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkCustomOrd = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalChron = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalBufLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalFpathLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalChronBufLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalChronFpathLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalChronBufSwitchGroupChron = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkGlobalChronBufSwitchGroupLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkBufferLocalChron = {
        link = "TrailblazerCustomMarkInvert",
      },
      TrailBlazerTrailMarkBufferLocalLineSorted = {
        link = "TrailblazerCustomMarkInvert",
      },
    },
  }
end

function M.config()
  init()
  keys()
  local trailblazer = require("trailblazer")
  trailblazer.setup(opts())

  vim.schedule(function()
    if utils.nvim_started_without_args() and not utils.cwd_is_home() then
      local common = require("trailblazer.trails.common")
      local original_method = common.focus_win_and_buf
      ---@diagnostic disable-next-line: duplicate-set-field
      common.focus_win_and_buf = function() return true end -- https://github.com/LeonHeidelbach/trailblazer.nvim/discussions/51#discussion-6054353
      trailblazer.load_trailblazer_state_from_file()
      common.focus_win_and_buf = original_method
    end
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Save a dir-specific session when you close Neovim",
    group = group,
    callback = function()
      if utils.nvim_started_without_args() and not utils.cwd_is_home() then
        trailblazer.save_trailblazer_state_to_file(nil, nil, false)
      end
    end,
  })
end

return M
