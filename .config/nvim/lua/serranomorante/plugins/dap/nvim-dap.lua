local constants = require("serranomorante.constants")
local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

---Debuggers can exist on one of 2 folders: `mason` or `debuggers`
---Mason: installed automatically. Usually for stable versions of packages.
---Debuggers: installed manually. Usually for nightly versions of packages. This is
---a custom folder on my system for things like `cpp_tools` or `vscode-js-debug`

---`h: dap.ext.vscode.load_launchjs`
local vscode_type_to_ft

return {
  "mfussenegger/nvim-dap",
  keys = {
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "DAP: Toggle Breakpoint (F9)" },
    { "<leader>dB", function() require("dap").clear_breakpoints() end, desc = "DAP: Clear Breakpoints" },
    {
      "<leader>dc",
      function()
        ---Load most recent `.vscode/launch.json` config
        ---https://github.com/mfussenegger/nvim-dap/issues/20#issuecomment-1356791734
        require("dap.ext.vscode").load_launchjs(nil, vscode_type_to_ft)
        require("dap").continue()
      end,
      desc = "DAP: Start/Continue (F5)",
    },
    {
      "<leader>dC",
      function()
        vim.ui.input({ prompt = "Condition: " }, function(condition)
          if condition then require("dap").set_breakpoint(condition) end
        end)
      end,
      desc = "DAP: Conditional Breakpoint (S-F9)",
    },
    {
      "<leader>d0",
      function()
        vim.ui.input({
          prompt = "Hit condition: ",
        }, function(hit_condition)
          if hit_condition then require("dap").set_breakpoint(nil, hit_condition) end
        end)
      end,
      desc = "DAP: Hit condition",
    },
    {
      "<leader>dl",
      function()
        vim.ui.input({ prompt = "Log message {foo}: " }, function(message)
          if message then require("dap").set_breakpoint(nil, nil, message) end
        end)
      end,
      desc = "DAP: Log Point",
    },
    { "<leader>di", function() require("dap").step_into() end, desc = "DAP: Step Into (F11)" },
    { "<leader>do", function() require("dap").step_over() end, desc = "DAP: Step Over (F10)" },
    { "<leader>dO", function() require("dap").step_out() end, desc = "DAP: Step Out (S-F11)" },
    { "<leader>dq", function() require("dap").close() end, desc = "DAP: Close Session" },
    { "<leader>dQ", function() require("dap").terminate() end, desc = "DAP: Terminate Session (S-F5)" },
    { "<leader>dp", function() require("dap").pause() end, desc = "DAP: Pause (F6)" },
    { "<leader>dr", function() require("dap").restart_frame() end, desc = "DAP: Restart (C-F5)" },
    {
      "<leader>dR",
      function() require("dap").repl.toggle({ wrap = false }, "belowright vsplit") end,
      desc = "DAP: Toggle REPL",
    },
    { "<leader>dS", function() require("dap").run_to_cursor() end, desc = "DAP: Run To Cursor" },
    { "<leader>dd", function() require("dap").focus_frame() end, desc = "DAP: Focus frame" },
    { "<leader>dh", function() require("dap.ui.widgets").hover() end, desc = "DAP: Debugger Hover" },
    {
      "<leader>ds",
      function()
        local ui = require("dap.ui.widgets")
        ui.centered_float(ui.scopes, { number = true, wrap = false, width = 999 })
      end,
      desc = 'DAP: Toggle "scopes" in floating window',
    },
  },
  init = function()
    vim.fn.sign_define("DapBreakpoint", { text = "⬤", texthl = "DapBreakpoint" })
    vim.fn.sign_define("DapBreakpointCondition", { text = " ", texthl = "DapBreakpoint" })
    vim.fn.sign_define("DapBreakpointRejected", { text = " ", texthl = "DapBreakpoint" })
    vim.fn.sign_define("DapLogPoint", { text = "", texthl = "DapLogPoint" })
    vim.fn.sign_define("DapStopped", { text = "󰁕 ", texthl = "DapStopped" })
  end,
  config = function()
    local dap = require("dap")
    local repl = require("dap.repl")
    local mason_registry = require("mason-registry")
    dap.set_log_level(vim.env.DAP_LOG_LEVEL or "INFO")

    ---https://github.com/mfussenegger/nvim-dap/issues/1141#issuecomment-2002575842
    dap.defaults.fallback.on_output = function(_, output_event)
      if string.find(output_event.output, "Could not read source map for file") then return end
      if output_event.category == "telemetry" then return end
      repl.append(output_event.output, "$", { newline = false })
    end

    ---╔══════════════════════════════════════╗
    ---║               Adapters               ║
    ---╚══════════════════════════════════════╝

    ---This env variable comes from my personal .bashrc file
    local system_node_version = vim.env.SYSTEM_DEFAULT_NODE_VERSION or "latest"
    ---Bypass volta's context detection to prevent running the debugger with unsupported node versions
    local node_path = utils.cmd({ "volta", "run", "--node", system_node_version, "which", "node" }):gsub("\n", "")
    if node_path then vim.g.node_system_executable = node_path end

    local vscode_js_debug_dap = mason_registry.get_package("js-debug-adapter")

    if vim.g.node_system_executable and vscode_js_debug_dap then
      local dap_executable = vscode_js_debug_dap:get_install_path() .. "/js-debug/src/dapDebugServer.js"

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
            command = vim.g.node_system_executable,
            args = { dap_executable, "${port}", host },
          },
        }
      end
    end

    local dap_executable = vim.fn.stdpath("data") .. "/debuggers/cpp_tools/extension/debugAdapters/bin/OpenDebugAD7"

    ---https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(gdb-via--vscode-cpptools)
    if vim.fn.executable(dap_executable) == 1 then
      dap.adapters.cppdbg = {
        id = "cppdbg",
        type = "executable",
        command = dap_executable,
      }
    end

    ---╔══════════════════════════════════════╗
    ---║           Configurations             ║
    ---╚══════════════════════════════════════╝

    local function url_prompt(default)
      default = default or "http://localhost:3000"
      local co = coroutine.running()
      return coroutine.create(function()
        vim.ui.input({ prompt = "Enter URL: ", default = default }, function(url)
          if url == nil or url == "" then
            return
          else
            coroutine.resume(co, url)
          end
        end)
      end)
    end

    for _, language in ipairs(constants.javascript_filetypes) do
      dap.configurations[language] = {
        {
          name = "DAP: Debug with PWA Chrome",
          type = "pwa-chrome",
          request = "launch",
          url = url_prompt,
        },
        ---Most of my dap configurations are too specific to add them here.
        ---I'm writing some nvim-dap guides in here:
        ---https://github.com/serranomorante/.dotfiles?tab=readme-ov-file#some-guides-to-my-self
      }
    end

    dap.configurations.c = {
      {
        name = "Launch file",
        request = "launch",
        type = "cppdbg",
        cwd = "${workspaceFolder}",
        program = "${fileDirname}/${fileBasenameNoExtension}",
        preLaunchTask = "C/C++: gcc build active file",
      },
      {
        name = "Launch file by custom path",
        type = "cppdbg",
        request = "launch",
        program = function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end,
        cwd = "${workspaceFolder}",
        preLaunchTask = "C/C++: gcc build active file",
      },
    }

    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    require("overseer").patch_dap(true)
    require("dap.ext.vscode").json_decode = require("overseer.json").decode

    ---Only needed if your debugging type doesn't match your language type.
    ---For example, python is not necessary on this table because its debugging type is "python"
    ---@diagnostic disable-next-line: unused-local
    vscode_type_to_ft = {
      ["node"] = constants.javascript_filetypes,
      ["chrome"] = constants.javascript_filetypes,
      ["firefox"] = constants.javascript_filetypes,
      ["pwa-node"] = constants.javascript_filetypes,
      ["pwa-chrome"] = constants.javascript_filetypes,
      ["pwa-msedge"] = constants.javascript_filetypes,
      ["node-terminal"] = constants.javascript_filetypes,
      ["pwa-extensionHost"] = constants.javascript_filetypes,
      ["cppdbg"] = constants.c_filetypes,
    }

    events.event("DAP" .. vim.api.nvim_get_option_value("filetype", { buf = 0 }))
  end,
}
