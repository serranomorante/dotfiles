#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless grep find
# dotfiles-test-firejail: disabled
# dotfiles-test-case: nvim-grep-short-term-blocked
# dotfiles-test-case: nvim-grep-long-term-runs
# dotfiles-test-case: nvim-find-short-term-blocked
# dotfiles-test-case: nvim-find-long-term-runs

# Purpose: Ensure Grep/Find reject search terms shorter than 5 characters.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"

require_tool() {
    local tool=$1
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'missing required tool: %s\n' "$tool" >&2
        exit 77
    fi
}

make_project() {
    local project="${DOTFILES_TEST_TMP}/grep-find-project"
    rm -rf "$project"
    mkdir -p "$project/sub"
    cat >"${project}/alpha.txt" <<'TXT'
all the things
wine_prefix_setup_prefixes here
TXT
    cat >"${project}/sub/beta.txt" <<'TXT'
wine_prefix_setup_prefixes again
TXT
    printf '%s\n' "$project"
}

run_nvim_lua() {
    local cwd=$1
    local lua_file=$2
    (
        cd "$cwd"
        "$nvim_bin" --headless -u NONE -i NONE --cmd "set rtp^=${rtp}" --cmd "set shadafile=NONE" -S "$lua_file"
    )
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

case "${DOTFILES_TEST_CASE:-}" in
nvim-grep-short-term-blocked)
    require_tool rg
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)

    lua_file="${DOTFILES_TEST_TMP}/grep-short-blocked.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.cmd.runtime({ "after/plugin/grep.lua", bang = true })' \
        '  vim.cmd.Grep("'"'"'all'"'"'")' \
        '  assert(vim.fn.getqflist({ size = 0 }).size == 0, "short grep should not populate quickfix")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-grep-long-term-runs)
    require_tool rg
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)

    lua_file="${DOTFILES_TEST_TMP}/grep-long-runs.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.cmd.runtime({ "after/plugin/grep.lua", bang = true })' \
        '  vim.cmd.Grep("'"'"'wine_prefix_setup_prefixes'"'"'")' \
        '  assert(vim.wait(3000, function() return vim.fn.getqflist({ size = 0 }).size >= 2 end), "long grep should populate quickfix")' \
        '  local qf = vim.fn.getqflist({ context = 0 })' \
        '  assert(qf.context ~= nil and qf.context.name == "user.grep", vim.inspect(qf.context))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-find-short-term-blocked)
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)

    lua_file="${DOTFILES_TEST_TMP}/find-short-blocked.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.globals")' \
        '  vim.cmd.runtime({ "after/plugin/find.lua", bang = true })' \
        '  local files = _G.user.findfunc("'"'"'all'"'"'")' \
        '  assert(#files == 0, "short find should return no files")' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-find-long-term-runs)
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)

    lua_file="${DOTFILES_TEST_TMP}/find-long-runs.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  require("serranomorante.globals")' \
        '  vim.cmd.runtime({ "after/plugin/find.lua", bang = true })' \
        '  local files = _G.user.findfunc("'"'"'alpha'"'"'")' \
        '  assert(#files > 0, "long find should return files")' \
        '  assert(files[1]:match("alpha%.txt$"), vim.inspect(files))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
