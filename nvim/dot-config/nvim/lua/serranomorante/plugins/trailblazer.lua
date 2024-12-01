local utils = require("serranomorante.utils")

local M = {}

local group = vim.api.nvim_create_augroup("trailblazer-custom-config", { clear = true })

---Check if trailblazer quickfix window is open
---@param any_qf boolean? Check if any qf window is open (not only trailblazer)
local function is_trailblazer_qf_open(any_qf)
  if require("trailblazer.trails").list.get_trailblazer_quickfix_buf(any_qf) then return true end
  return false
end

local function init()
  local color = "#005869"
  vim.api.nvim_set_hl(0, "TrailblazerCustomMark", { fg = color, bg = "NONE" })
  vim.api.nvim_set_hl(0, "TrailblazerCustomMarkInvert", { fg = "NONE", bg = color })
  vim.api.nvim_set_hl(0, "TrailblazerSelectedStack", { fg = "NvimLightGreen", bold = true })

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
      local list = require("trailblazer.trails.list")
      if is_trailblazer_qf_open() then list.register_quickfix_keybindings(list.config.quickfix_mappings) end
    end,
  })
end

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
    local trails = require("trailblazer.trails")
    if is_trailblazer_qf_open(true) and not is_trailblazer_qf_open() then return utils.next_qf_item() end
    if #trails.stacks.current_trail_mark_stack == 0 then return vim.notify("Marks empty", vim.log.levels.WARN) end
    require("trailblazer").switch_trail_mark_stack(trails.stacks.current_trail_mark_stack_name, false) -- fixes trails getting stuck
    require("trailblazer").move_to_nearest(vim.api.nvim_get_current_buf(), "fpath_down", "lin_char_dist")
  end, { desc = "Trailblazer: Move to the next global trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-k>", function()
    local trails = require("trailblazer.trails")
    if is_trailblazer_qf_open(true) and not is_trailblazer_qf_open() then return utils.prev_qf_item() end
    if #trails.stacks.current_trail_mark_stack == 0 then return vim.notify("Marks empty", vim.log.levels.WARN) end
    require("trailblazer").switch_trail_mark_stack(trails.stacks.current_trail_mark_stack_name, false) -- fixes trails getting stuck
    require("trailblazer").move_to_nearest(vim.api.nvim_get_current_buf(), "fpath_up", "lin_char_dist")
  end, { desc = "Trailblazer: Move to the previous global trail mark" })

  vim.keymap.set({ "n", "v" }, "<A-m>", function()
    require("trailblazer").toggle_trail_mark_list("quickfix")
    if is_trailblazer_qf_open() then vim.cmd.wincmd({ args = { "p" } }) end
  end, { desc = "Trailblazer: Toggle a global list of all trail marks" })

  vim.keymap.set(
    { "n", "v" },
    "<A-S>",
    function() require("trailblazer").delete_all_trail_marks() end,
    { desc = "Trailblazer: Delete all trail marks globally" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-.>",
    function() require("trailblazer").switch_to_next_trail_mark_stack() end,
    { desc = "Trailblazer: Switch to the next trail mark stack" }
  )

  vim.keymap.set(
    { "n", "v" },
    "<A-,>",
    function() require("trailblazer").switch_to_previous_trail_mark_stack() end,
    { desc = "Trailblazer: Switch to the previous trail mark stack" }
  )

  vim.keymap.set("n", "<A-`>", function()
    vim.ui.input({ prompt = "Stack Name: " }, function(input)
      if not input then return end
      require("trailblazer").switch_trail_mark_stack(input, false)
      require("trailblazer").new_trail_mark()
      utils.cmd({ "notify-send", input, "--icon=bookmarks" })
    end)
  end, { desc = "Trailblazer: Add new trail mark stack" })

  vim.keymap.set("n", "<A-'>", function()
    local hi = require("fzf-lua.utils").ansi_from_hl
    local stacks = require("trailblazer.trails").stacks.trail_mark_stack_list
    local sorted_stacks = require("trailblazer.trails").stacks.get_sorted_stack_names()
    local current_stack = require("trailblazer.trails").stacks.current_trail_mark_stack_name
    vim.ui.select(sorted_stacks, {
      prompt = "Choose a stack ",
      format_item = function(item)
        local fitem = item
        local count = vim.tbl_count(stacks[item] and stacks[item].stack or {})
        if item == current_stack then fitem = hi("TrailblazerSelectedStack", " " .. fitem) end -- add icon to current stack
        fitem = string.sub(" ", #tostring(vim.fn.index(sorted_stacks, item) + 1), 1) .. fitem -- left align
        return count > 0 and fitem .. hi("Comment", string.format(" (%d)", count)) or fitem -- add trails count if more than zero
      end,
    }, require("trailblazer").switch_trail_mark_stack)
  end, { desc = "Trailblazer: Switch stack" })

  vim.keymap.set("n", "<A-s>", function()
    local modes = require("trailblazer.trails").config.custom.available_trail_mark_modes
    local current_mode = require("trailblazer.trails").config.custom.current_trail_mark_mode
    modes = vim.tbl_filter(function(mode) return mode ~= current_mode end, modes)
    vim.ui.select(modes, { prompt = current_mode .. " " }, function(choice)
      if choice then require("trailblazer").set_trail_mark_select_mode(choice, false) end
    end)
  end)

  vim.keymap.set("n", '<A-">', function()
    local stacks = require("trailblazer.trails").stacks.get_sorted_stack_names()
    local current_stack = require("trailblazer.trails").stacks.current_trail_mark_stack_name
    stacks = vim.tbl_filter(function(stack) return stack ~= current_stack end, stacks)
    vim.ui.select(stacks, { prompt = "Delete stack " }, function(choice)
      if choice then require("trailblazer").delete_trail_mark_stack(choice) end
    end)
  end, { desc = "Trailblazer: Delete stack" })
end

local function opts()
  return {
    auto_save_trailblazer_state_on_exit = false,
    auto_load_trailblazer_state_on_enter = false,
    trail_options = {
      current_trail_mark_stack_sort_mode = "chron_asc",
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
    local common = require("trailblazer.trails.common")
    local original_method = common.focus_win_and_buf
    ---@diagnostic disable-next-line: duplicate-set-field
    common.focus_win_and_buf = function() return true end -- https://github.com/LeonHeidelbach/trailblazer.nvim/discussions/51#discussion-6054353
    trailblazer.load_trailblazer_state_from_file()
    common.focus_win_and_buf = original_method
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Save a dir-specific session when you close Neovim",
    group = group,
    callback = function()
      if utils.nvim_started_without_args() then trailblazer.save_trailblazer_state_to_file(nil, nil, false) end
    end,
  })
end

return M
