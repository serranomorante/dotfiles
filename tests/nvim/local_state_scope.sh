#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless local-state
# dotfiles-test-firejail: disabled
# dotfiles-test-readonly: /home/aaaa/.local/bin/nvim
# dotfiles-test-readonly: /home/aaaa/.local/lib/nvim
# dotfiles-test-readonly: /home/aaaa/.local/share/nvim
# dotfiles-test-case: nvim-local-state-normal-cwd
# dotfiles-test-case: nvim-local-state-cwd-isolation
# dotfiles-test-case: nvim-local-state-file-inside-cwd-expands-home
# dotfiles-test-case: nvim-local-state-broad-cwd-disabled
# dotfiles-test-case: nvim-local-state-secret-undo-disabled

# Purpose: Fast checks for CWD-scoped Neovim shada/undo persistence.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

run_nvim_lua_file() {
    local cwd=$1
    local lua_file=$2
    local runtime_parent="/run/user/$(id -u)"
    local runtime_dir
    local rc=0

    runtime_dir=$(mktemp -d "${runtime_parent}/dotfiles-test-nvim.XXXXXX" 2>/dev/null || mktemp -d "${DOTFILES_TEST_TMP}/dotfiles-test-nvim.XXXXXX")
    mkdir -p "$runtime_dir"
    (
        cd "$cwd"
        export XDG_RUNTIME_DIR="$runtime_dir"
        "$nvim_bin" \
            --headless \
            -u NONE \
            -c "set rtp^=${rtp}" \
            -S "$lua_file"
    ) || rc=$?
    rm -rf "$runtime_dir"
    return "$rc"
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

case "${DOTFILES_TEST_CASE:-}" in
nvim-local-state-normal-cwd)
    project="${DOTFILES_TEST_TMP}/project-a"
    mkdir -p "$project"
    lua_file="${DOTFILES_TEST_TMP}/normal-cwd.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local servername = vim.env.XDG_RUNTIME_DIR .. "/kitty-cwd-test.nvim.sock"' \
        '  local state = utils.local_state_config(vim.fn.getcwd(), servername, vim.fn.stdpath("cache"))' \
        '  assert(state.persist == true, "local state should persist")' \
        '  assert(state.shadafile:match("/shadadir/" .. state.cwd_key .. "%.nvim%.shada$"), state.shadafile)' \
        '  assert(state.undodir:match("/fundo%-by%-cwd/" .. state.cwd_key .. "$"), state.undodir)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project" "$lua_file"
    ;;
nvim-local-state-cwd-isolation)
    project_a="${DOTFILES_TEST_TMP}/project-a"
    project_b="${DOTFILES_TEST_TMP}/project-b"
    mkdir -p "$project_a" "$project_b"
    lua_file="${DOTFILES_TEST_TMP}/cwd-isolation.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local servername = vim.env.XDG_RUNTIME_DIR .. "/kitty-cwd-test.nvim.sock"' \
        '  local state = utils.local_state_config(vim.fn.getcwd(), servername, vim.fn.stdpath("cache"))' \
        '  vim.fn.writefile({ state.shadafile, state.undodir }, vim.env.DOTFILES_TEST_TMP .. "/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") .. ".state")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project_a" "$lua_file"
    run_nvim_lua_file "$project_b" "$lua_file"
    if cmp -s "${DOTFILES_TEST_TMP}/project-a.state" "${DOTFILES_TEST_TMP}/project-b.state"; then
        printf 'different CWDs produced identical local-state paths\n' >&2
        exit 1
    fi
    ;;
nvim-local-state-file-inside-cwd-expands-home)
    project="${HOME}/project-paths"
    mkdir -p "$project"
    printf 'marked\n' >"${project}/marked.txt"
    lua_file="${DOTFILES_TEST_TMP}/file-inside-cwd-expands-home.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local cwd = vim.env.HOME .. "/project-paths"' \
        '  assert(utils.file_inside_cwd("~/project-paths/marked.txt", cwd), "tilde path should be inside absolute cwd")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project" "$lua_file"
    ;;
nvim-local-state-broad-cwd-disabled)
    mkdir -p "${HOME}/data/repos" "${HOME}/data/secrets"
    lua_file="${DOTFILES_TEST_TMP}/broad-cwd.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local servername = vim.env.XDG_RUNTIME_DIR .. "/kitty-cwd-test.nvim.sock"' \
        '  local state = utils.local_state_config(vim.fn.getcwd(), servername, vim.fn.stdpath("cache"))' \
        '  assert(state.persist == false, "local state should not persist")' \
        '  assert(state.shadafile == "NONE", "shadafile should be NONE, got " .. state.shadafile)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    for cwd in "$HOME" "$HOME/data" "$HOME/data/repos" "$HOME/data/secrets"; do
        run_nvim_lua_file "$cwd" "$lua_file"
    done
    ;;
nvim-local-state-secret-undo-disabled)
    project="${DOTFILES_TEST_TMP}/project-secrets"
    mkdir -p "$project"
    lua_file="${DOTFILES_TEST_TMP}/secret-undo.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local names = { ".env", ".env.test", "token.json", "secret.pem", "credentials.key", "api-key.txt" }' \
        '  for _, name in ipairs(names) do' \
        '    local path = vim.fn.getcwd() .. "/" .. name' \
        '    assert(utils.is_secret_persistent_undo_path(path), name .. " should disable persistent undo")' \
        '  end' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project" "$lua_file"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
