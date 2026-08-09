#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless nnn explorer
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-case: nvim-nnn-quick-access-path-from-visual-selection
# dotfiles-test-case: nvim-nnn-quick-access-opens-selected-directory
# dotfiles-test-case: nvim-nnn-quick-access-rejects-nonexistent-path

# Purpose: Verify the visual <leader>e nnn quick-access helpers extract the
# selected path, only open nnn when that path exists, and report an error in
# Neovim when it does not.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

make_fake_kitty_bin() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/kitty-nnn-quick-access" <<'BASH'
#!/bin/sh
printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/nnn.calls"
BASH
    chmod +x "${bin}/kitty-nnn-quick-access"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
nvim-nnn-quick-access-path-from-visual-selection)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "$project"
    touch "$project/real.txt"
    NVIM_LOG_FILE="${DOTFILES_TEST_TMP}/nvim.log" \
        "$nvim_bin" --headless -n -u NONE \
        -c "set rtp^=${rtp}" \
        -c "lua local function main()
  local utils = require(\"serranomorante.utils\")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { \"prefix ${project}/real.txt suffix\" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(\"vE\", true, false, true), \"x\", false)
  local path = utils.path_from_visual_selection()
  assert(path == \"${project}/real.txt\", \"expected selected path, got \" .. vim.inspect(path))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end"
    ;;
nvim-nnn-quick-access-opens-selected-directory)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "$project"
    touch "$project/real.txt"
    bin=$(make_fake_kitty_bin)
    NVIM_LOG_FILE="${DOTFILES_TEST_TMP}/nvim.log" \
        PATH="${bin}:${PATH}" \
        "$nvim_bin" --headless -n -u NONE \
        -c "set rtp^=${rtp}" \
        -c "lua local function main()
  local utils = require(\"serranomorante.utils\")
  local launched = utils.open_nnn_quick_access_at(\"${project}/real.txt\")
  assert(launched, \"expected open_nnn_quick_access_at to launch for an existing path\")
  assert(vim.wait(2000, function()
    return vim.fn.filereadable(\"${DOTFILES_TEST_TMP}/nnn.calls\") == 1
  end, 20), \"kitty-nnn-quick-access was not launched\")
  local calls = vim.fn.readfile(\"${DOTFILES_TEST_TMP}/nnn.calls\")
  assert(calls[1] == \"${project}\", \"expected kitty-nnn-quick-access target \" .. vim.inspect(calls))
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end"
    ;;
nvim-nnn-quick-access-rejects-nonexistent-path)
    bin=$(make_fake_kitty_bin)
    NVIM_LOG_FILE="${DOTFILES_TEST_TMP}/nvim.log" \
        PATH="${bin}:${PATH}" \
        "$nvim_bin" --headless -n -u NONE \
        -c "set rtp^=${rtp}" \
        -c "lua local function main()
  local utils = require(\"serranomorante.utils\")
  local missing = \"${DOTFILES_TEST_TMP}/does-not-exist/file.txt\"
  vim.api.nvim_echo = function(chunks, _, opts)
    if chunks and chunks[1] and chunks[1][1] then vim.g.nnn_echo = chunks[1][1] end
  end
  local launched = utils.open_nnn_quick_access_at(missing)
  assert(not launched, \"expected open_nnn_quick_access_at to refuse a nonexistent path\")
  assert(vim.g.nnn_echo and vim.g.nnn_echo:find(\"Path not found\", 1, true), \"expected Path not found error, got \" .. vim.inspect(vim.g.nnn_echo))
  assert(vim.fn.filereadable(\"${DOTFILES_TEST_TMP}/nnn.calls\") == 0, \"kitty-nnn-quick-access must not launch for a nonexistent path\")
  vim.cmd.qa({ bang = true })
end
local ok, err = xpcall(main, debug.traceback)
if not ok then print(err); vim.cmd.cquit({ bang = true }) end"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
