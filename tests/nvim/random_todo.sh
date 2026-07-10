#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim remind firejail
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: random-todo-ignores-example-sources

# Purpose: Verify the workspace random TODO picker ignores generated/example Markdown.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless -u NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

case "${DOTFILES_TEST_CASE:-}" in
random-todo-ignores-example-sources)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/notes"; vim.fn.mkdir(p.."/misc/tasks","p"); vim.fn.mkdir(p.."/docs/agents","p"); vim.fn.mkdir(p.."/misc/agent-runs/2026-05","p"); vim.fn.writefile({"# Real","- [ ] **Real task**"}, p.."/misc/tasks/real.md"); vim.fn.writefile({"# Example","- [ ] **Documentation task**"}, p.."/docs/agents/remind-usage.md"); vim.fn.writefile({"# Example","- [ ] **Generated task**"}, p.."/misc/agent-runs/2026-05/result.md"); vim.cmd.cd({ args = { p } }); vim.cmd.runtime("after/plugin/random_todo.lua"); vim.cmd.RandomTodo(); local items=vim.fn.getqflist(); assert(#items == 1, vim.inspect(items)); assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(items[1].bufnr), ":t") == "real.md", vim.inspect(items)); vim.cmd.qa({bang=true})'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
