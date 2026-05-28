#!/usr/bin/env bash

# Purpose: Shared Firejail launcher for the dotfiles test runner.

dotfiles_test_inside_firejail() {
    [[ "${container:-}" == "firejail" || -n "${FIREJAIL_SANDBOX:-}" || -n "${FIREJAIL_NAME:-}" ]]
}

dotfiles_test_firejail_run() {
    local repo_root=$1
    local tmp_root=$2
    local test_file=$3
    local test_case=$4
    local readonly_paths=${5:-}
    local home_dir="${tmp_root}/home"
    local xdg_config="${tmp_root}/xdg-config"
    local xdg_cache="${tmp_root}/xdg-cache"
    local xdg_data="${tmp_root}/xdg-data"
    local path_value=${PATH:-/usr/local/bin:/usr/bin:/bin}
    local lang_value=${LANG:-C.UTF-8}
    local term_value=${TERM:-dumb}

    mkdir -p "$home_dir" "$xdg_config" "$xdg_cache" "$xdg_data"

    if [[ "${DOTFILES_TEST_NO_FIREJAIL:-0}" == "1" ]]; then
        (
            cd "$repo_root"
            env -i \
                HOME="$home_dir" \
                XDG_CONFIG_HOME="$xdg_config" \
                XDG_CACHE_HOME="$xdg_cache" \
                XDG_DATA_HOME="$xdg_data" \
                TMPDIR="$tmp_root" \
                PATH="$path_value" \
                LANG="$lang_value" \
                TERM="$term_value" \
                DOTFILES_TEST_ROOT="$repo_root" \
                DOTFILES_TEST_TMP="$tmp_root" \
                DOTFILES_TEST_CASE="$test_case" \
                bash "$test_file"
        )
        return
    fi

    command -v firejail >/dev/null 2>&1 || {
        printf 'firejail is required; install test dependencies or set DOTFILES_TEST_NO_FIREJAIL=1 for debugging\n' >&2
        return 1
    }

    if dotfiles_test_inside_firejail && [[ "${DOTFILES_TEST_ALLOW_NESTED_FIREJAIL:-0}" != "1" ]]; then
        printf 'refusing to run nested firejail without prior investigation; set DOTFILES_TEST_ALLOW_NESTED_FIREJAIL=1 only for explicit experiments\n' >&2
        return 1
    fi

    local readonly_args=()
    local readonly_path
    while IFS= read -r readonly_path; do
        [[ -n "$readonly_path" ]] || continue
        [[ "$readonly_path" = /* ]] || {
            printf 'readonly sandbox path must be absolute: %s\n' "$readonly_path" >&2
            return 1
        }
        [[ -e "$readonly_path" ]] || {
            printf 'readonly sandbox path does not exist: %s\n' "$readonly_path" >&2
            return 1
        }
        readonly_args+=("--whitelist=${readonly_path}" "--read-only=${readonly_path}")
    done <<<"$readonly_paths"

    (
        cd "$repo_root"
        firejail \
            --quiet \
            --noprofile \
            --net=none \
            "--whitelist=${repo_root}" \
            "--read-only=${repo_root}" \
            "${readonly_args[@]}" \
            "--whitelist=${tmp_root}" \
            "--read-write=${tmp_root}" \
            env -i \
            HOME="$home_dir" \
            XDG_CONFIG_HOME="$xdg_config" \
            XDG_CACHE_HOME="$xdg_cache" \
            XDG_DATA_HOME="$xdg_data" \
            TMPDIR="$tmp_root" \
            PATH="$path_value" \
            LANG="$lang_value" \
            TERM="$term_value" \
            DOTFILES_TEST_ROOT="$repo_root" \
            DOTFILES_TEST_TMP="$tmp_root" \
            DOTFILES_TEST_CASE="$test_case" \
            bash "$test_file"
    )
}
