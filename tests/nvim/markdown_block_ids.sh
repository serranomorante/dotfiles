#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless firejail
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: markdown-block-ids-loads
# dotfiles-test-case: markdown-block-ids-wikilink-file
# dotfiles-test-case: markdown-block-ids-markdown-link
# dotfiles-test-case: markdown-block-ids-local-wikilink
# dotfiles-test-case: markdown-block-ids-go-to-id
# dotfiles-test-case: markdown-block-ids-go-to-id-ignores-example-sources
# dotfiles-test-case: markdown-block-ids-command-go-to-id-with-modified-buffer
# dotfiles-test-case: markdown-block-ids-command-go-to-id
# dotfiles-test-case: markdown-block-ids-heading-passthrough

# Purpose: Persist behavior tests for the Markdown @id block resolver.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua() {
    local lua=$1
    "$nvim_bin" --headless -u NONE -c "set rtp^=${rtp}" -c "lua ${lua}"
}

case "${DOTFILES_TEST_CASE:-}" in
markdown-block-ids-loads)
    run_nvim_lua 'require("serranomorante.markdown_block_ids"); vim.cmd.qa({bang=true})'
    ;;
markdown-block-ids-wikilink-file)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-wiki"; vim.fn.mkdir(p,"p"); vim.fn.writefile({}, p.."/.marksman.toml"); vim.fn.writefile({"[[b#^foo]]"}, p.."/a.md"); vim.fn.writefile({"Target paragraph","@id foo","","Detached","","@id foo"}, p.."/b.md"); vim.cmd.edit(p.."/a.md"); vim.api.nvim_win_set_cursor(0,{1,4}); local ok=require("serranomorante.markdown_block_ids").goto_block_id_under_cursor(0); assert(ok); vim.defer_fn(function() assert(vim.fn.expand("%:t") == "b.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 2); vim.cmd.qa({bang=true}) end, 300)'
    ;;
markdown-block-ids-markdown-link)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-md"; vim.fn.mkdir(p,"p"); vim.fn.writefile({"[go](b.md#^foo)"}, p.."/a.md"); vim.fn.writefile({"Target paragraph","@tags #hello","@id foo"}, p.."/b.md"); vim.cmd.edit(p.."/a.md"); vim.api.nvim_win_set_cursor(0,{1,3}); local ok=require("serranomorante.markdown_block_ids").goto_block_id_under_cursor(0); assert(ok); assert(vim.fn.expand("%:t") == "b.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 3); vim.cmd.qa({bang=true})'
    ;;
markdown-block-ids-local-wikilink)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-local"; vim.fn.mkdir(p,"p"); vim.fn.writefile({"[[#^foo]]","","Target paragraph","@id foo"}, p.."/a.md"); vim.cmd.edit(p.."/a.md"); vim.api.nvim_win_set_cursor(0,{1,4}); local ok=require("serranomorante.markdown_block_ids").goto_block_id_under_cursor(0); assert(ok); assert(vim.fn.expand("%:t") == "a.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 4); vim.cmd.qa({bang=true})'
    ;;
markdown-block-ids-go-to-id)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-by-id"; vim.fn.mkdir(p,"p"); vim.fn.writefile({"[[b#^foo]]"}, p.."/a.md"); vim.fn.writefile({"Target paragraph","@tags #hello","@id foo"}, p.."/b.md"); vim.cmd.edit(p.."/a.md"); local ok=require("serranomorante.markdown_block_ids").goto_block_id("foo", p); assert(ok); vim.defer_fn(function() assert(vim.fn.expand("%:t") == "b.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 3); vim.cmd.qa({bang=true}) end, 300)'
    ;;
markdown-block-ids-go-to-id-ignores-example-sources)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-by-id-exclusions"; vim.fn.mkdir(p.."/misc/tasks","p"); vim.fn.mkdir(p.."/docs/agents","p"); vim.fn.mkdir(p.."/misc/agent-runs/2026-05","p"); vim.fn.writefile({"Real paragraph","@id foo"}, p.."/misc/tasks/real.md"); vim.fn.writefile({"Example paragraph","@id foo"}, p.."/docs/agents/remind-usage.md"); vim.fn.writefile({"Generated paragraph","@id foo"}, p.."/misc/agent-runs/2026-05/result.md"); local ok=require("serranomorante.markdown_block_ids").goto_block_id("foo", p); assert(ok); vim.defer_fn(function() assert(vim.fn.expand("%:t") == "real.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 2); vim.cmd.qa({bang=true}) end, 300)'
    ;;
markdown-block-ids-command-go-to-id-with-modified-buffer)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-command-modified"; vim.fn.mkdir(p,"p"); vim.fn.writefile({"Target paragraph","@id foo"}, p.."/b.md"); vim.cmd.cd({ args = { p } }); vim.cmd.enew(); vim.api.nvim_buf_set_lines(0,0,-1,false,{"unsaved scratch text"}); local scratch=vim.api.nvim_get_current_buf(); assert(vim.bo.modified); vim.cmd.runtime("after/plugin/markdown_block_ids.lua"); vim.cmd("GoToFoamBlockById foo"); vim.defer_fn(function() assert(vim.fn.expand("%:t") == "b.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 2); assert(vim.api.nvim_buf_is_loaded(scratch)); assert(vim.api.nvim_get_option_value("modified", { buf = scratch })); vim.cmd.qa({bang=true}) end, 300)'
    ;;
markdown-block-ids-command-go-to-id)
    run_nvim_lua 'local p=vim.env.DOTFILES_TEST_TMP.."/mdid-command"; vim.fn.mkdir(p,"p"); vim.fn.writefile({}, p.."/.marksman.toml"); vim.fn.writefile({"Target paragraph","@id foo"}, p.."/b.md"); vim.cmd.edit(p.."/b.md"); vim.cmd.runtime("after/plugin/markdown_block_ids.lua"); vim.cmd("GoToFoamBlockById foo"); vim.defer_fn(function() assert(vim.fn.expand("%:t") == "b.md"); assert(vim.api.nvim_win_get_cursor(0)[1] == 2); vim.cmd.qa({bang=true}) end, 300)'
    ;;
markdown-block-ids-heading-passthrough)
    run_nvim_lua 'vim.cmd.enew(); vim.bo.modified=false; vim.api.nvim_buf_set_lines(0,0,-1,false,{"[[b#heading]]"}); vim.bo.modified=false; vim.api.nvim_win_set_cursor(0,{1,4}); assert(require("serranomorante.markdown_block_ids").goto_block_id_under_cursor(0) == false); vim.cmd.qa({bang=true})'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
