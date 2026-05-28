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
markdown-block-ids-heading-passthrough)
    run_nvim_lua 'vim.cmd.enew(); vim.bo.modified=false; vim.api.nvim_buf_set_lines(0,0,-1,false,{"[[b#heading]]"}); vim.bo.modified=false; vim.api.nvim_win_set_cursor(0,{1,4}); assert(require("serranomorante.markdown_block_ids").goto_block_id_under_cursor(0) == false); vim.cmd.qa({bang=true})'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
