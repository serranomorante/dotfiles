#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim headless ctags e2e
# dotfiles-test-firejail: disabled
# dotfiles-test-case: nvim-ctags-links-generate-structural-tags
# dotfiles-test-case: nvim-ctags-links-native-tag-navigation
# dotfiles-test-case: nvim-ctags-links-ctrl-bracket-register
# dotfiles-test-case: nvim-ctags-links-ctrl-bracket-set-fact
# dotfiles-test-case: nvim-ctags-links-tag-references-qf
# dotfiles-test-case: nvim-ctags-links-ctrl-bracket-manual-priority
# dotfiles-test-case: nvim-ctags-links-ctrl-bracket-hyphen-role

# Purpose: Exercise the ctags structural-link workflow end to end.

nvim_bin=${NVIM_BIN:-/home/aaaa/.local/bin/nvim}
rtp="${DOTFILES_TEST_ROOT}/nvim/dot-config/nvim"
refresh_ctags="${DOTFILES_TEST_ROOT}/nvim/bin/dotfiles-refresh-ctags"

require_tool() {
    local tool=$1
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'missing required tool: %s\n' "$tool" >&2
        exit 77
    fi
}

make_project() {
    local project="${DOTFILES_TEST_TMP}/ctags-project"
    rm -rf "$project"
    mkdir -p "$project/group_vars" "$project/roles/wine-installer-poll/tasks" "$project/tasks"
    cat >"${project}/group_vars/main.yml" <<'YAML'
# ctags-link: wine_prefix_setup_prefixes, manual_alias, second_alias
arch_wine_prefix_setups:
  - name: reaper
wine_prefix_setup_prefixes: []
arch_music_plugins_wine_prefix: value
YAML
    cat >"${project}/roles/wine-installer-poll/tasks/main.yml" <<'YAML'
---
- name: role entrypoint
YAML
    cat >"${project}/tasks/main.yml" <<'YAML'
- name: call role
  ansible.builtin.include_role:
    name: wine-installer-poll
- name: inspect remote commit
  ansible.builtin.command:
    argv:
      - git
      - ls-remote
      - git://git.example.org/project
      - HEAD
  register: var_remote_commit
  changed_when: false
- name: set marker
  ansible.builtin.set_fact:
    dwm_patch_marker: "project-{{ var_remote_commit.stdout.split()[0] }}-patch-stack-v1"
- name: record marker
  ansible.builtin.include_role:
    name: dotfiles-markers
    tasks_from: record
  vars:
    dotfiles_marker_name: "{{ dwm_patch_marker }}"
    dotfiles_marker_register: var_dwm_patch_marker
YAML
    printf '%s\n' "$project"
}

run_refresh_ctags() {
    local project=$1
    (
        cd "$project"
        "$refresh_ctags"
    )
}

run_nvim() {
    local cwd=$1
    shift
    local runtime_dir
    runtime_dir=$(mktemp -d "${DOTFILES_TEST_TMP}/nvim-runtime.XXXXXX")
    (
        cd "$cwd"
        XDG_RUNTIME_DIR="$runtime_dir" "$nvim_bin" --headless -u NONE -i NONE --cmd "set rtp^=${rtp}" --cmd "set shadafile=NONE" "$@"
    )
    rm -rf "$runtime_dir"
}

run_nvim_lua() {
    local cwd=$1
    local lua_file=$2
    run_nvim "$cwd" -S "$lua_file"
}

write_lua() {
    local path=$1
    shift
    printf '%s\n' "$@" >"$path"
}

case "${DOTFILES_TEST_CASE:-}" in
nvim-ctags-links-generate-structural-tags)
    require_tool ctags
    require_tool rg
    project=$(make_project)
    run_refresh_ctags "$project"

    rg -q $'^wine_prefix_setup_prefixes\tgroup_vars/main.yml\t2;"\tl\tline:2$' "${project}/tags"
    ! rg -q $'^wine_prefix_setup_prefixes\tgroup_vars/main.yml\t/\\^wine_prefix_setup_prefixes:' "${project}/tags"
    rg -q $'^arch_music_plugins_wine_prefix\tgroup_vars/main.yml\t' "${project}/tags"
    rg -q $'^wine-installer-poll\troles/wine-installer-poll/tasks/main.yml\t1;"\tr\tline:1$' "${project}/tags"
    rg -q $'^var_remote_commit\ttasks/main.yml\t/var_remote_commit/;"\ta\tline:11$' "${project}/tags"
    rg -q $'^dwm_patch_marker\ttasks/main.yml\t/dwm_patch_marker:/;"\tf\tline:15$' "${project}/tags"
    rg -q $'^manual_alias\tgroup_vars/main.yml\t2;"\tl\tline:2$' "${project}/tags"
    rg -q $'^second_alias\tgroup_vars/main.yml\t2;"\tl\tline:2$' "${project}/tags"
    LC_ALL=C sort -c "${project}/tags"
    ;;
nvim-ctags-links-native-tag-navigation)
    require_tool ctags
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-native-navigation.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.o.tags = "tags"' \
        '  vim.o.tagbsearch = true' \
        '  vim.cmd("tag arch_music_plugins_wine_prefix")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("group_vars/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 5, vim.fn.line("."))' \
        '  vim.cmd("tag wine_prefix_setup_prefixes")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("group_vars/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 2, vim.fn.line("."))' \
        '  vim.cmd("tag wine-installer-poll")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("roles/wine%-installer%-poll/tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 1, vim.fn.line("."))' \
        '  vim.cmd("tag var_remote_commit")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 11, vim.fn.line("."))' \
        '  assert(vim.fn.col(".") == 13, vim.fn.col("."))' \
        '  vim.cmd("tag dwm_patch_marker")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 15, vim.fn.line("."))' \
        '  assert(vim.fn.col(".") == 5, vim.fn.col("."))' \
        '  vim.cmd("tag manual_alias")' \
        '  assert(vim.api.nvim_buf_get_name(0):match("group_vars/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 2, vim.fn.line("."))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-ctags-links-ctrl-bracket-register)
    require_tool ctags
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-ctrl-bracket-register.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.o.tags = "tags"' \
        '  vim.cmd.edit("tasks/main.yml")' \
        '  vim.cmd.normal({ "15G1|", bang = true })' \
        '  assert(vim.fn.search("var_remote_commit", "c", 15) > 0, "missing usage")' \
        '  assert(vim.fn.expand("<cword>") == "var_remote_commit", vim.fn.expand("<cword>"))' \
        '  vim.cmd.normal({ "\029", bang = true })' \
        '  assert(vim.api.nvim_buf_get_name(0):match("tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 11, vim.fn.line("."))' \
        '  assert(vim.fn.col(".") == 13, vim.fn.col("."))' \
        '  assert(vim.fn.getline("."):match("^  register: var_remote_commit"), vim.fn.getline("."))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-ctags-links-ctrl-bracket-set-fact)
    require_tool ctags
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-ctrl-bracket-set-fact.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.o.tags = "tags"' \
        '  vim.cmd.edit("tasks/main.yml")' \
        '  vim.cmd.normal({ "21G1|", bang = true })' \
        '  assert(vim.fn.search("dwm_patch_marker", "c", 21) > 0, "missing usage")' \
        '  assert(vim.fn.expand("<cword>") == "dwm_patch_marker", vim.fn.expand("<cword>"))' \
        '  vim.cmd.normal({ "\029", bang = true })' \
        '  assert(vim.api.nvim_buf_get_name(0):match("tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 15, vim.fn.line("."))' \
        '  assert(vim.fn.col(".") == 5, vim.fn.col("."))' \
        '  assert(vim.fn.getline("."):match("^    dwm_patch_marker:"), vim.fn.getline("."))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-ctags-links-tag-references-qf)
    require_tool ctags
    require_tool rg
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-tag-references-qf.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.cmd.runtime({ "after/plugin/ctags.lua", bang = true })' \
        '  vim.cmd.edit("tasks/main.yml")' \
        '  vim.bo.tagfunc = "v:lua.vim.lsp.tagfunc"' \
        '  vim.cmd.normal({ "15G5|", bang = true })' \
        '  assert(vim.fn.expand("<cword>") == "dwm_patch_marker", vim.fn.expand("<cword>"))' \
        '  local mapping = vim.fn.maparg("<leader>cr", "n", false, true)' \
        '  assert(mapping.desc == "Find ctags references", vim.inspect(mapping))' \
        '  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>cr", true, false, true), "x", false)' \
        '  assert(vim.wait(3000, function() return vim.fn.getqflist({ size = 0 }).size >= 2 end), "quickfix was not populated")' \
        '  local qf = vim.fn.getqflist({ items = 0, size = 0, winid = 0, title = 0 })' \
        '  assert(qf.winid and qf.winid > 0, "quickfix window was not opened")' \
        '  assert(qf.title:match("^%[Tag references%] %d+ results:"), qf.title)' \
        '  local context = vim.fn.getqflist({ context = 0 }).context' \
        '  assert(context.tag.name == "dwm_patch_marker", vim.inspect(context))' \
        '  assert(context.tag.filename:match("tasks/main%.yml$"), vim.inspect(context.tag))' \
        '  assert(context.tag.kind == "f", vim.inspect(context.tag))' \
        '  local found_definition, found_usage, found_tags_file = false, false, false' \
        '  for _, item in ipairs(qf.items) do' \
        '    local filename = vim.fn.bufname(item.bufnr)' \
        '    if filename:match("tasks/main%.yml$") and item.lnum == 15 and item.col == 5 then found_definition = true end' \
        '    if filename:match("tasks/main%.yml$") and item.lnum == 21 and item.col == 31 then found_usage = true end' \
        '    if filename:match("/tags$") then found_tags_file = true end' \
        '  end' \
        '  assert(found_definition, "missing set_fact definition reference")' \
        '  assert(found_usage, "missing later fact usage reference")' \
        '  assert(not found_tags_file, "tags file should be excluded from references")' \
        '  vim.cmd.edit("group_vars/main.yml")' \
        '  vim.cmd.normal({ "4G1|", bang = true })' \
        '  assert(vim.fn.expand("<cword>") == "wine_prefix_setup_prefixes", vim.fn.expand("<cword>"))' \
        '  vim.cmd.TagReferences()' \
        '  assert(vim.wait(3000, function() return vim.fn.getqflist({ size = 0 }).size == 2 end), vim.inspect(vim.fn.getqflist({ size = 0 })))' \
        '  local alias_context = vim.fn.getqflist({ context = 0 }).context' \
        '  assert(vim.deep_equal(alias_context.reference_names, { "wine_prefix_setup_prefixes", "arch_wine_prefix_setups" }), vim.inspect(alias_context))' \
        '  local alias_qf = vim.fn.getqflist({ items = 0 })' \
        '  local found_alias_target, found_alias_reference, found_ctags_link = false, false, false' \
        '  for _, item in ipairs(alias_qf.items) do' \
        '    local filename = vim.fn.bufname(item.bufnr)' \
        '    if filename:match("group_vars/main%.yml$") and item.lnum == 2 and item.col == 1 then found_alias_target = true end' \
        '    if filename:match("group_vars/main%.yml$") and item.lnum == 4 and item.col == 1 then found_alias_reference = true end' \
        '    if item.text:match("ctags%-link:") then found_ctags_link = true end' \
        '  end' \
        '  assert(found_alias_target, "missing ctags-link target symbol reference")' \
        '  assert(found_alias_reference, "missing ctags-link alias reference")' \
        '  assert(not found_ctags_link, "ctags-link metadata should be excluded from references")' \
        '  vim.cmd("TagReferences not_a_tag")' \
        '  local missing = vim.fn.getqflist({ context = 0, size = 0, title = 0 })' \
        '  assert(missing.size == 0, vim.inspect(missing))' \
        '  assert(missing.context.tag == "not_a_tag", vim.inspect(missing.context))' \
        '  assert(missing.context.tag_resolved == false, vim.inspect(missing.context))' \
        '  assert(missing.title == "[Tag references] no ctags entry: not_a_tag", missing.title)' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-ctags-links-ctrl-bracket-hyphen-role)
    require_tool ctags
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-ctrl-bracket.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  package.preload["serranomorante.plugins.lsp.utils"] = function() return { enable = function() end } end' \
        '  vim.cmd("filetype plugin on")' \
        '  vim.o.tags = "tags"' \
        '  vim.cmd.edit("tasks/main.yml")' \
        '  vim.bo.filetype = "yaml.ansible"' \
        '  vim.cmd.runtime({ "after/ftplugin/yaml.lua", bang = true })' \
        '  vim.cmd.normal({ "3G11|", bang = true })' \
        '  assert(vim.fn.expand("<cword>") == "wine-installer-poll", vim.fn.expand("<cword>"))' \
        '  vim.cmd.normal({ "\029", bang = true })' \
        '  assert(vim.api.nvim_buf_get_name(0):match("roles/wine%-installer%-poll/tasks/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 1, vim.fn.line("."))' \
        '  vim.cmd.qa({ bang = true })' \
        'end' \
        'local ok, err = xpcall(main, debug.traceback)' \
        'if not ok then print(err); vim.cmd.cquit({ bang = true }) end'
    run_nvim_lua "$project" "$lua_file"
    ;;
nvim-ctags-links-ctrl-bracket-manual-priority)
    require_tool ctags
    [[ -x "$nvim_bin" ]] || {
        printf 'missing nvim binary: %s\n' "$nvim_bin" >&2
        exit 77
    }
    project=$(make_project)
    run_refresh_ctags "$project"

    lua_file="${DOTFILES_TEST_TMP}/ctags-ctrl-bracket-manual-priority.lua"
    write_lua "$lua_file" \
        'local function main()' \
        '  vim.o.tags = "tags"' \
        '  vim.cmd.edit("group_vars/main.yml")' \
        '  vim.cmd.normal({ "4G1|", bang = true })' \
        '  assert(vim.fn.expand("<cword>") == "wine_prefix_setup_prefixes", vim.fn.expand("<cword>"))' \
        '  vim.cmd.normal({ "\029", bang = true })' \
        '  assert(vim.api.nvim_buf_get_name(0):match("group_vars/main%.yml$"), vim.api.nvim_buf_get_name(0))' \
        '  assert(vim.fn.line(".") == 2, vim.fn.line("."))' \
        '  assert(vim.fn.getline("."):match("^arch_wine_prefix_setups:"), vim.fn.getline("."))' \
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
