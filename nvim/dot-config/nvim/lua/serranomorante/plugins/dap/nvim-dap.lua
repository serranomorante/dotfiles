local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
local dap_utils = require("serranomorante.plugins.dap.dap-utils")
local binaries = require("serranomorante.binaries")

local M = {}

---`h: dap.ext.vscode.load_launchjs`
local vscode_type_to_ft
local log_is_trace = vim.env.DAP_LOG_LEVEL == "TRACE" or false

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
    ---Load most recent `.vscode/launch.json` config
    ---https://github.com/mfussenegger/nvim-dap/issues/20#issuecomment-1356791734
    require("dap.ext.vscode").load_launchjs(nil, vscode_type_to_ft)
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
    require("dap").terminate()
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
    function() require("dap").repl.open({ wrap = false }, "edit") end,
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
  vim.fn.sign_define("DapBreakpoint", { text = "⬤", texthl = "DapBreakpoint" })
  vim.fn.sign_define("DapBreakpointCondition", { text = " ", texthl = "DapBreakpoint" })
  vim.fn.sign_define("DapBreakpointRejected", { text = " ", texthl = "DapBreakpoint" })
  vim.fn.sign_define("DapLogPoint", { text = "", texthl = "DapLogPoint" })
  vim.fn.sign_define("DapStopped", { text = "󰁕 ", texthl = "DapStopped" })

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
  dap.set_log_level(vim.env.DAP_LOG_LEVEL or "INFO")
  dap.defaults.fallback.focus_terminal = true
  dap.defaults.fallback.force_external_terminal = true
  dap.defaults.fallback.switchbuf = "usevisible,usetab,uselast"

  ---https://github.com/mfussenegger/nvim-dap/issues/1141#issuecomment-2002575842
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
    utils.cmd({ "notify-send", "Breakpoint stopped", "--icon=dialog-information" })
  end

  ---╔══════════════════════════════════════╗
  ---║               Adapters               ║
  ---╚══════════════════════════════════════╝

  local ok, override_node = pcall(binaries.system_default_node)

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
        args = { "/usr/bin/dapDebugServer.js", "${port}", host },
      },
    }
  end

  local dap_executable = vim.env.HOME .. "/apps/lang-tools/cpptools/extension/debugAdapters/bin/OpenDebugAD7"

  ---https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(gdb-via--vscode-cpptools)
  if vim.fn.executable(dap_executable) == 1 then
    dap.adapters.cppdbg = {
      id = "cppdbg",
      type = "executable",
      command = dap_executable,
    }
  end

  dap.adapters.bashdb = {
    name = "bashdb",
    type = "executable",
    command = vim.env.HOME .. "/apps/lang-tools/bash-debug-adapter",
  }

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
        name = "DAP: chrome client launch",
        type = "pwa-chrome",
        request = "launch",
        sourceMaps = true,
        url = function()
          return coroutine.create(function(dap_run_co)
            local items = { "3000", "3001", "3002", "3003", "3004" } -- TODO: get the ports programatically
            items = vim.tbl_map(function(item) return "http://localhost:" .. item end, items)
            vim.ui.select(items, { label = "Port> " }, function(choice)
              if choice then coroutine.resume(dap_run_co, choice) end
            end)
          end)
        end,
        webRoot = function() return dap_utils.choose_path_relative_to_file(javascript_project_files) end,
        userDataDir = true,
        trace = log_is_trace,
      },
      {
        name = "DAP: chrome client attach",
        type = "pwa-chrome",
        request = "attach",
        port = 9222, -- Start chrome with `google-chrome-stable --remote-debugging-port=9222`
        sourceMaps = true,
        protocol = "inspector",
        webRoot = function() return dap_utils.choose_path_relative_to_file(javascript_project_files) end,
        pauseForSourceMap = false, -- https://github.com/microsoft/vscode-js-debug/blob/main/OPTIONS.md#pauseforsourcemap-5
        urlFilter = function() -- This allows me to use the same chrome instance for normal browsing
          return coroutine.create(function(dap_run_co)
            vim.ui.input({
              prompt = "Enter urlFilter: ",
              default = "localhost:*", -- https://stackoverflow.com/a/47410471
            }, function(input)
              return (input and input ~= "") and coroutine.resume(dap_run_co, input) or dap.ABORT
            end)
          end)
        end,
        skipFiles = {
          "**/node_modules/**",
        },
        trace = log_is_trace,
      },
      { -- Tested on next.js 14.2.3. It doesn't work on next.js 14.0.4
        name = "DAP: Next.js server attach",
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
        cwd = function() return dap_utils.choose_path_relative_to_file(javascript_project_files) end,
        skipFiles = {
          "/**", -- same as default value: https://github.com/microsoft/vscode-js-debug/blob/main/OPTIONS.md#default-value-25
          "**/node_modules/**",
          "!**/node_modules/my-module/**",
        },
        trace = log_is_trace,
      },
      --- Next.js server "launch" is not included here because it can be too specific depending on the project
    }
  end

  dap.configurations.c = {
    {
      name = "DAP: c/c++ build active file & launch it",
      request = "launch",
      type = "cppdbg",
      cwd = "${workspaceFolder}",
      program = "${fileDirname}/${fileBasenameNoExtension}",
      preLaunchTask = "vscode-tasks: C/C++: gcc build active file",
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

  ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
  require("overseer").enable_dap(true)
  require("dap.ext.vscode").json_decode = require("overseer.json").decode

  ---Only needed if your debugging type doesn't match your language type.
  ---For example, python is not necessary on this table because its debugging type is "python"
  ---@diagnostic disable-next-line: unused-local
  vscode_type_to_ft = {
    ["node"] = constants.javascript_aliases,
    ["chrome"] = constants.javascript_aliases,
    ["firefox"] = constants.javascript_aliases,
    ["pwa-node"] = constants.javascript_aliases,
    ["pwa-chrome"] = constants.javascript_aliases,
    ["pwa-msedge"] = constants.javascript_aliases,
    ["node-terminal"] = constants.javascript_aliases,
    ["pwa-extensionHost"] = constants.javascript_aliases,
    ["cppdbg"] = constants.c_aliases,
  }

  vim.cmd.packadd("osv")
  require("serranomorante.plugins.dap.one-small-step-for-vimkind").config()
end

return M
