#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless overseer markdown pandoc latex
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-case: export-markdown-includes-the-code-wrap-header

# Purpose: Guard the code-wrapping half of the markdown export task. A PDF page
#   has no horizontal scroll, and the fancyvrb Verbatim that pandoc builds its
#   code blocks on runs a long line off the paper without a word of warning, so
#   the header that turns wrapping on is part of the task's contract.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"
header="${rtp}/lua/overseer/template/editor-tasks/export_markdown/code-wrap.tex"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless -u NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

case "${DOTFILES_TEST_CASE:-}" in
export-markdown-includes-the-code-wrap-header)
    run_nvim_lua 'local template = require("overseer.template.editor-tasks.TASK__export_markdown"); local task = template.builder(); local want = ("--include-in-header=%s/lua/overseer/template/editor-tasks/export_markdown/code-wrap.tex"):format(vim.fn.stdpath("config")); assert(vim.tbl_contains(task.args, want), vim.inspect(task.args)); vim.cmd.qa({bang=true})'

    test -f "$header"
    grep -Fq '\usepackage{fvextra}' "$header"
    grep -Fq 'DefineVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\},breaklines,breakanywhere}' "$header"
    grep -Fq 'RecustomVerbatimEnvironment{verbatim}{Verbatim}{breaklines,breakanywhere}' "$header"
    grep -Fq 'renewcommand{\texttt}' "$header"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
