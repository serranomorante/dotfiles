local constants = require("serranomorante.constants")
local publish_diagnostics = "textDocument/publishDiagnostics"
local default_publish_diagnostics = vim.lsp.handlers[publish_diagnostics]

if not constants.BINARIES.marksman then return {} end

-- marksman runs unsandboxed on the host, so launch it inside a systemd user
-- scope to cap its CPU/memory via cgroup limits (see the `marksman` profile in
-- app-resources.vars.yml). Fall back to a direct launch if the cgroup launcher
-- isn't installed.
local marksman_bin = constants.BINARIES.marksman()
local cgroup_launch = vim.fn.expand("~/bin/app-cgroup-launch")
local cmd = vim.fn.executable(cgroup_launch) == 1
    and { cgroup_launch, "marksman", marksman_bin, "server" }
  or { marksman_bin, "server" }

---@type vim.lsp.Config
return {
  cmd = cmd,
  filetypes = constants.markdown_aliases,
  handlers = {
    [publish_diagnostics] = function(err, result, ctx, config)
      require("serranomorante.markdown_block_ids").filter_marksman_diagnostics(result)
      return default_publish_diagnostics(err, result, ctx, config)
    end,
  },
  root_markers = { ".marksman.toml", ".git" },
}
