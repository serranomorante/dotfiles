#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless marks
# dotfiles-test-firejail: disabled
# dotfiles-test-case: nvim-global-marks-list-reads-label
# dotfiles-test-case: nvim-global-marks-label-scoped-by-cwd

# Purpose: Verify Neovim global marks integrate with the shared label store.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"
marks_label_bin="${DOTFILES_TEST_ROOT}/utilities/bin/marks-label"

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
        export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/state"
        export MARK_LABEL_BIN="$marks_label_bin"
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
nvim-global-marks-list-reads-label)
    project="${DOTFILES_TEST_TMP}/project-a"
    mkdir -p "$project"
    printf 'one\ntwo\nthree\n' >"${project}/note.txt"
    lua_file="${DOTFILES_TEST_TMP}/list-reads-label.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local gm = require("serranomorante.global_marks")' \
        '  local bin = vim.env.MARK_LABEL_BIN' \
        '  vim.cmd.edit({ args = { vim.fn.getcwd() .. "/note.txt" } })' \
        '  vim.api.nvim_win_set_cursor(0, { 2, 0 })' \
        '  vim.cmd.normal({ "mA", bang = true })' \
        '  vim.fn.system({ bin, "set", utils.local_state_cwd_key(), "A-label", "my label" })' \
        '  local marks = gm.list()' \
        '  assert(marks.A ~= nil, "mark A should be listed")' \
        '  assert(marks.A.label == "my label", "label should be read back, got: " .. tostring(marks.A.label))' \
        '  assert(marks.A.pos[2] == 2, "line should be 2, got: " .. tostring(marks.A.pos[2]))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project" "$lua_file"
    ;;
nvim-global-marks-label-scoped-by-cwd)
    project_a="${DOTFILES_TEST_TMP}/project-a"
    project_b="${DOTFILES_TEST_TMP}/project-b"
    mkdir -p "$project_a" "$project_b"
    printf 'one\ntwo\n' >"${project_a}/note.txt"
    printf 'one\ntwo\n' >"${project_b}/note.txt"
    lua_file="${DOTFILES_TEST_TMP}/scope-by-cwd.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  local utils = require("serranomorante.utils")' \
        '  local gm = require("serranomorante.global_marks")' \
        '  local bin = vim.env.MARK_LABEL_BIN' \
        '  local scope = utils.local_state_cwd_key()' \
        '  vim.cmd.edit({ args = { vim.fn.getcwd() .. "/note.txt" } })' \
        '  vim.cmd.normal({ "mA", bang = true })' \
        '  vim.fn.system({ bin, "set", scope, "A-label", "cwd " .. vim.fn.getcwd() })' \
        '  local marks = gm.list()' \
        '  assert(marks.A.label == "cwd " .. vim.fn.getcwd(), "label should match cwd, got: " .. tostring(marks.A and marks.A.label))' \
        '  vim.fn.writefile({ scope }, vim.env.DOTFILES_TEST_TMP .. "/scope-" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua_file "$project_a" "$lua_file"
    run_nvim_lua_file "$project_b" "$lua_file"
    scope_a=$(cat "${DOTFILES_TEST_TMP}/scope-project-a")
    scope_b=$(cat "${DOTFILES_TEST_TMP}/scope-project-b")
    [ "$scope_a" != "$scope_b" ]
    [ -f "${DOTFILES_TEST_TMP}/state/dotfiles/marks/${scope_a}.labels" ]
    [ -f "${DOTFILES_TEST_TMP}/state/dotfiles/marks/${scope_b}.labels" ]
    refute cmp -s \
        "${DOTFILES_TEST_TMP}/state/dotfiles/marks/${scope_a}.labels" \
        "${DOTFILES_TEST_TMP}/state/dotfiles/marks/${scope_b}.labels"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
