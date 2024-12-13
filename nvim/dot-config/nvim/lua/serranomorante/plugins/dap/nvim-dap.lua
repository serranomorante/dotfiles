local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
local dap_utils = require("serranomorante.plugins.dap.dap-utils")
local binaries = require("serranomorante.binaries")

local M = {}

local LOG_IS_TRACE = vim.env.DAP_LOG_LEVEL == "TRACE" or false

local keys = function()
  vim.keymap.set(
    "n",
    "<leader>db",
    function() require("dap").toggle_breakpoint() end,
    { desc = "DAP: Toggle Breakpoint" }
  )
  vim.keymap.set(
    "n",
    "<leader>dB",
    function() require("dap").clear_breakpoints() end,
    { desc = "DAP: Clear Breakpoints" }
  )
  vim.keymap.set("n", "<leader>dc", function()
    require("dap").continue()
    vim.defer_fn(function() vim.cmd.redrawstatus() end, 100)
  end, { desc = "DAP: Start/Continue (F5)" })
  vim.keymap.set("n", "<leader>dC", function()
    vim.ui.input({ prompt = "Condition: " }, function(condition)
      if condition then require("dap").set_breakpoint(condition) end
    end)
  end, { desc = "DAP: Conditional Breakpoint (S-F9)" })
  vim.keymap.set("n", "<leader>d0", function()
    vim.ui.input({
      prompt = "Hit condition: ",
    }, function(hit_condition)
      if hit_condition then require("dap").set_breakpoint(nil, hit_condition) end
    end)
  end, { desc = "DAP: Hit condition" })
  vim.keymap.set("n", "<leader>dl", function()
    vim.ui.input({ prompt = "Log message {foo}: " }, function(message)
      if message then require("dap").set_breakpoint(nil, nil, message) end
    end)
  end, { desc = "DAP: Log Point" })
  vim.keymap.set("n", "<leader>di", function() require("dap").step_into() end, { desc = "DAP: Step Into" })
  vim.keymap.set("n", "<leader>do", function() require("dap").step_over() end, { desc = "DAP: Step Over" })
  vim.keymap.set("n", "<leader>dO", function() require("dap").step_out() end, { desc = "DAP: Step Out" })
  vim.keymap.set("n", "<leader>dq", function()
    require("dap").close()
    vim.defer_fn(function() vim.cmd.redrawstatus() end, 100)
  end, { desc = "DAP: Close Session" })
  vim.keymap.set("n", "<leader>dQ", function()
    ---https://github.com/mfussenegger/nvim-dap/issues/1166#issuecomment-2521447005
    require("dap").terminate({ hierarchy = true })
    vim.defer_fn(function() vim.cmd.redrawstatus() end, 100)
  end, { desc = "DAP: Terminate Session" })
  vim.keymap.set(
    "n",
    "<leader>dD",
    function() require("dap").disconnect({ terminateDebuggee = false }) end,
    { desc = "DAP: Disconnect adapter" }
  )
  vim.keymap.set("n", "<leader>dp", function() require("dap").pause() end, { desc = "DAP: Pause" })
  vim.keymap.set("n", "<leader>dr", function() require("dap").restart_frame() end, { desc = "DAP: Restart" })
  vim.keymap.set(
    "n",
    "<leader>dR",
    function() require("dap").repl.open({ wrap = false, number = true }, "rightbelow 50 vsplit") end,
    { desc = "DAP: Toggle REPL" }
  )
  vim.keymap.set("n", "<leader>dS", function() require("dap").run_to_cursor() end, { desc = "DAP: Run To Cursor" })
  vim.keymap.set("n", "<leader>dd", function() require("dap").focus_frame() end, { desc = "DAP: Focus frame" })
  vim.keymap.set("n", "<leader>dh", function() require("dap.ui.widgets").hover() end, { desc = "DAP: Debugger Hover" })
  vim.keymap.set("n", "<leader>ds", function()
    local ui = require("dap.ui.widgets")
    ui.centered_float(ui.scopes, { number = true, wrap = false, width = 999 })
  end, { desc = 'DAP: Toggle "scopes" in floating window' })
  vim.keymap.set(
    "n",
    ---https://github.com/mfussenegger/nvim-dap/issues/1288#issuecomment-2248506225
    "<leader>da",
    function()
      local ui = require("dap.ui.widgets")
      ui.centered_float(ui.sessions, { number = true, wrap = false, width = 999 })
    end,
    { desc = 'DAP: Toggle "sessions" in floating window' }
  )
end

local init = function()
  vim.fn.sign_define("DapBreakpoint", { text = "⬤", texthl = "DapBreakpoint", priority = 21 })
  vim.fn.sign_define("DapBreakpointCondition", { text = " ", texthl = "DapBreakpoint", priority = 21 })
  vim.fn.sign_define("DapBreakpointRejected", { text = " ", texthl = "DapBreakpoint", priority = 21 })
  vim.fn.sign_define("DapLogPoint", { text = "", texthl = "DapLogPoint", priority = 21 })
  vim.fn.sign_define("DapStopped", { text = "󰁕 ", texthl = "DapStopped", priority = 22 })

  vim.api.nvim_create_autocmd("FileType", {
    desc = 'Attach autocompletion to "dap-repl" filetype',
    pattern = "dap-repl",
    group = vim.api.nvim_create_augroup("repl-autocompletion", { clear = true }),
    callback = function() require("dap.ext.autocompl").attach() end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    desc = 'Always start "dap-repl" in normal mode', -- similar to what is done on ex command line window
    pattern = "\\[dap-repl*\\]",
    group = vim.api.nvim_create_augroup("repl-stopinsert", { clear = true }),
    command = "stopinsert",
  })
end

M.config = function()
  init()
  keys()
  local dap = require("dap")
  local repl = require("dap.repl")
  ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
  require("overseer").enable_dap(true)
  require("dap.ext.vscode").json_decode = require("overseer.json").decode
  dap.set_log_level(vim.env.DAP_LOG_LEVEL or "INFO")
  dap.defaults.fallback.focus_terminal = true
  dap.defaults.fallback.force_external_terminal = true
  dap.defaults.fallback.switchbuf = "usevisible,usetab,uselast"

  ---https://github.com/mfussenegger/nvim-dap/issues/1141#issuecomment-2002575842
  ---@param _ dap.Session
  ---@param output_event dap.OutputEvent
  dap.defaults.fallback.on_output = function(_, output_event)
    if output_event.category == "stderr" then
      if string.find(output_event.output, "Could not read source map for file") then return end
    elseif output_event.category == "telemetry" then
      return
    else
      repl.append(output_event.output, "$", { newline = false })
    end
  end

  local dap_events = { "initialized", "breakpoint", "continued", "exited", "terminated", "thread", "stopped" }
  for event_index, event in ipairs(dap_events) do
    dap.listeners.after["event_" .. event]["statusline" .. event_index] = function() vim.cmd.redrawstatus() end
  end

  dap.listeners.after.event_stopped["system_notification"] = function()
    utils.cmd({ "notify-send", string.format("Breakpoint stopped %s", vim.fn.getcwd()), "--icon=dialog-information" })
  end

  ---╔══════════════════════════════════════╗
  ---║               Adapters               ║
  ---╚══════════════════════════════════════╝

  local ok, override_node = pcall(binaries.system_default_node)

  if binaries.vscode_js_debug_dap_executable() then
    for _, type in ipairs({
      "node",
      "chrome",
      "pwa-node",
      "pwa-chrome",
      "pwa-msedge",
      "node-terminal",
      "pwa-extensionHost",
    }) do
      local host = "localhost"
      dap.adapters[type] = {
        type = "server",
        host = host,
        port = "${port}",
        executable = {
          command = (ok and override_node) and override_node or "node",
          args = { binaries.vscode_js_debug_dap_executable(), "${port}", host },
        },
      }
    end
  end

  ---https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(gdb-via--vscode-cpptools)
  if vim.fn.executable(binaries.cppdbg_dap_executable()) == 1 then
    dap.adapters.cppdbg = {
      id = "cppdbg",
      type = "executable",
      command = binaries.cppdbg_dap_executable(),
    }
  end

  if vim.fn.executable(binaries.bashdb_dap_executable()) == 1 then
    dap.adapters.bashdb = {
      name = "bashdb",
      type = "executable",
      command = binaries.bashdb_dap_executable(),
    }
  end

  if vim.fn.executable(binaries.debugpy_dap_executable()) == 1 then
    dap.adapters.python = function(cb, config)
      if config.request == "attach" then
        ---@diagnostic disable-next-line: undefined-field
        local port = (config.connect or config).port
        ---@diagnostic disable-next-line: undefined-field
        local host = (config.connect or config).host or "127.0.0.1"
        cb({
          type = "server",
          port = assert(port, "`connect.port` is required for a python `attach` configuration"),
          host = host,
          enrich_config = dap_utils.python_enrich_config,
          options = {
            source_filetype = "python",
          },
        })
      else
        cb({
          type = "executable",
          command = binaries.debugpy_dap_executable(),
          args = { "-m", "debugpy.adapter" },
          enrich_config = dap_utils.python_enrich_config,
          options = {
            source_filetype = "python",
          },
        })
      end
    end
  end

  ---╔══════════════════════════════════════╗
  ---║           Configurations             ║
  ---╚══════════════════════════════════════╝

  --[[ 
      # Javascript/Next.js/Typescript/Turborepo:
      # I prefer the "attach" configs so that closing nvim doesn't kill the debug adapters (google-chrome-stable or next-server process)
      # You cannot reuse the same ports (for example, on `--remote-debugging-port=9222` or `--inspect=9229`) across nvim-dap sessions.
      # Either you open new ones (new instances of chrome, new instances of next-server) and attach to those new ports, or stop your
      # running nvim-dap sessions (that use those ports) and start a new one (my workflow, don't pay too much attention to this).
    ]]

  local javascript_project_files = { "tsconfig.json", "package.json", "jsconfig.json", ".git" }
  for _, language in ipairs(constants.javascript_aliases) do
    dap.configurations[language] = {
      {
        name = "DAP: chrome client attach",
        type = "pwa-chrome",
        request = "attach",
        port = 9222, -- Start chrome with `google-chrome-stable --remote-debugging-port=9222`
        sourceMaps = true,
        protocol = "inspector",
        webRoot = function() return dap_utils.pick_workspace_relative_to_file(javascript_project_files) end,
        pauseForSourceMap = false, -- https://github.com/microsoft/vscode-js-debug/blob/main/OPTIONS.md#pauseforsourcemap-5
        urlFilter = function()
          ---Pick a specific tab to debug
          return dap_utils.pick_url_filter_from_tabs()
        end,
        skipFiles = {
          "**/node_modules/**",
        },
        trace = LOG_IS_TRACE,
      },
      { -- Tested on next.js 14.2.3. It doesn't work on next.js 14.0.4
        name = "DAP: next.js server attach",
        type = "pwa-node",
        request = "attach",
        processId = function() return require("dap.utils").pick_process({ filter = "^next.server.*" }) end,
        port = function()
          -- TODO: get the ports programatically
          return coroutine.create(function(dap_run_co)
            vim.ui.input({
              prompt = "Enter port: ",
              default = "9230", --[[
                    You should start your dev server with `NODE_OPTIONS='--inspect' ...`
                    "--inspect option was detected, the Next.js router server should be inspected at port 9230"
                  ]]
            }, function(input)
              return (input and input ~= "") and coroutine.resume(dap_run_co, input) or dap.ABORT
            end)
          end)
        end,
        cwd = function() return dap_utils.pick_workspace_relative_to_file(javascript_project_files) end,
        trace = LOG_IS_TRACE,
      },
      --- Next.js server "launch" is not included here because it can be too specific depending on the project
    }
  end

  for _, language in ipairs({ "c", "cpp" }) do
    dap.configurations[language] = {
      {
        name = "DAP: c/c++ build active file & launch it",
        request = "launch",
        type = "cppdbg",
        cwd = "${workspaceFolder}",
        program = "${fileDirname}/${fileBasenameNoExtension}",
        preLaunchTask = "vscode-tasks-gcc-build-active-file",
      },
      {
        name = "DAP: c/c++ pick and launch executable",
        type = "cppdbg",
        request = "launch",
        program = function() return require("dap.utils").pick_file() end,
        cwd = "${workspaceFolder}",
        environment = {
          {
            ---I override the `DAP_OVERRIDED_DISPLAY` env variable (which fallbacks to the original DISPLAY value)
            ---from an overseer task that setups my dwm debugging session
            name = "DISPLAY",
            value = "${env:DAP_OVERRIDED_DISPLAY}",
          },
        },
      },
    }
  end

  dap.configurations.sh = {
    {
      type = "bashdb",
      request = "launch",
      name = "DAP: sh debug launch file",
      showDebugOutput = true,
      pathBashdb = vim.env.HOME .. "/apps/lang-tools/bash-debug-adapter/extension/bashdb_dir/bashdb",
      pathBashdbLib = vim.env.HOME .. "/apps/lang-tools/bash-debug-adapter/extension/bashdb_dir",
      trace = true,
      file = "${command:pickFile}",
      program = "${command:pickFile}",
      cwd = "${workspaceFolder}",
      pathCat = "cat",
      pathBash = "/bin/bash",
      pathMkfifo = "mkfifo",
      pathPkill = "pkill",
      args = {},
      env = {},
      terminalKind = "integrated",
    },
  }

  vim.cmd.packadd("osv")
  require("serranomorante.plugins.dap.one-small-step-for-vimkind").config()
end

return M
