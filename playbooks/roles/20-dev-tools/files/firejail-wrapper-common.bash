#!/usr/bin/env bash

# @description Print a wrapper-scoped error message to stderr and terminate.
# @arg $@ string Error message fragments to print as a single message.
# @stderr Error message prefixed with SCRIPT_NAME when available.
# @exitcode 1 Always exits with status 1.
die() {
    printf '%s: %s\n' "${SCRIPT_NAME:-firejail-wrapper}" "$*" >&2
    exit 1
}

# @description Ensure that an environment variable is set and non-empty.
# @arg $1 name Environment variable name to validate.
# @stderr Validation error emitted via die when the variable is missing.
# @exitcode 0 If the variable is set.
# @exitcode 1 If the variable is missing or empty.
require_env() {
    local name=$1
    [[ -n "${!name:-}" ]] || die "missing required environment variable ${name}"
}

# @description Resolve an existing directory to its canonical absolute path.
# @arg $1 path Directory path to resolve.
# @stdout Canonical absolute directory path on success.
# @exitcode 0 If the directory exists and can be resolved.
# @exitcode 1 If the path is missing, not a directory, or cannot be entered.
canonicalize_existing_dir() {
    local path=$1

    [[ -d "$path" ]] || return 1
    cd "$path" >/dev/null 2>&1 || return 1
    pwd -P
}

# @description Build the per-user Firejail profile path for a named profile.
# @arg $1 path Home directory used as the Firejail config root.
# @arg $2 string Firejail profile filename, such as fj-py.profile.
# @stdout Absolute path under ~/.config/firejail for the requested profile.
# @exitcode 0 If the profile path is computed successfully.
# @exitcode 1 If the provided home root is empty.
firejail_profile_path() {
    local home_root=$1
    local profile_name=$2

    [[ -n "$home_root" ]] || die "HOME is required to resolve firejail profiles"
    printf '%s/.config/firejail/%s\n' "$home_root" "$profile_name"
}

# @description Append one or more validated filesystem permissions to FIREJAIL_ARGS.
# @arg $1 mode Access mode: ro or rw.
# @arg $2 string Newline-delimited absolute paths to expose inside Firejail.
# @set FIREJAIL_ARGS string[] Appends whitelist and read-only/read-write flags.
# @exitcode 0 If every provided path is valid or the input is empty.
# @exitcode 1 If a path is relative, missing, or the mode is unsupported.
append_paths() {
    local mode=$1
    local raw=$2
    local line

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == /* ]] || die "${mode} path must be absolute: ${line}"

        case "$mode" in
        ro)
            [[ -e "$line" ]] || die "${mode} path does not exist: ${line}"
            FIREJAIL_ARGS+=("--whitelist=$line" "--read-only=$line")
            ;;
        rw)
            [[ -e "$line" ]] || die "${mode} path does not exist: ${line}"
            FIREJAIL_ARGS+=("--whitelist=$line" "--read-write=$line")
            ;;
        *)
            die "unsupported path mode: ${mode}"
            ;;
        esac
    done <<<"$raw"
}

# @description Append a single optional path to FIREJAIL_ARGS when it exists.
# @arg $1 mode Access mode: ro or rw.
# @arg $2 path Optional absolute path to expose if present.
# @set FIREJAIL_ARGS string[] Appends Firejail flags only when the path exists.
# @exitcode 0 If the path is empty, missing, or appended successfully.
# @exitcode 1 If the provided mode is unsupported or the path is invalid.
append_optional_path() {
    local mode=$1
    local path=${2:-}

    [[ -n "$path" ]] || return 0
    [[ -e "$path" ]] || return 0
    append_paths "$mode" "$path"
}

# @description Initialize FIREJAIL_ARGS with the selected profile and network policy.
# @arg $1 path Readable Firejail profile path.
# @arg $2 network-mode Network policy: online, local, or offline.
# @set FIREJAIL_ARGS string[] Replaces the array with a fresh firejail command.
# @exitcode 0 If the profile exists and the network mode is supported.
# @exitcode 1 If the profile is missing or the network mode is invalid.
init_firejail_args() {
    local profile_path=$1
    local network_mode=$2

    [[ -r "$profile_path" ]] || die "missing firejail profile: ${profile_path}"

    FIREJAIL_ARGS=(
        /usr/bin/firejail
        "--profile=${profile_path}"
    )

    case "$network_mode" in
    online)
        FIREJAIL_ARGS+=(--protocol=unix,inet,inet6)
        ;;
    local)
        FIREJAIL_ARGS+=(--protocol=unix)
        ;;
    offline)
        FIREJAIL_ARGS+=(--net=none)
        ;;
    *)
        die "unsupported network mode: ${network_mode}"
        ;;
    esac
}

# @description Initialize ENV_ARGS with a clean env invocation.
# @noargs
# @set ENV_ARGS string[] Replaces the array with /usr/bin/env -i.
# @exitcode 0 Always succeeds.
init_clean_env() {
    ENV_ARGS=(/usr/bin/env -i)
}

# @description Append a literal environment assignment to ENV_ARGS.
# @arg $1 name Environment variable name.
# @arg $2 string Environment variable value.
# @set ENV_ARGS string[] Appends NAME=value to the clean environment command.
# @exitcode 0 Always succeeds.
append_env_literal() {
    local name=$1
    local value=$2

    ENV_ARGS+=("${name}=${value}")
}

# @description Append an environment assignment only when the source variable is set.
# @arg $1 name Environment variable name to read from the current shell.
# @set ENV_ARGS string[] Appends NAME=value only when the source variable is non-empty.
# @exitcode 0 Always succeeds.
append_env_if_set() {
    local name=$1

    [[ -n "${!name:-}" ]] || return 0
    append_env_literal "$name" "${!name}"
}

# @description Append selected environment variables to ENV_ARGS when they are set.
# @arg $1 string Newline-delimited environment variable names to forward.
# @set ENV_ARGS string[] Appends NAME=value pairs for each present variable.
# @exitcode 0 Always succeeds.
append_env_names_if_set() {
    local raw=$1
    local name

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        append_env_if_set "$name"
    done <<<"$raw"
}

# @description Copy common terminal and session variables into ENV_ARGS when present.
# @noargs
# @set ENV_ARGS string[] Appends terminal-related variables such as TERM and DISPLAY.
# @exitcode 0 Always succeeds.
append_common_terminal_env() {
    local key

    for key in TERM COLORTERM LANG LC_ALL LC_CTYPE USER LOGNAME SHELL DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR; do
        append_env_if_set "$key"
    done
}

# @description Validate the generic wrapper command shape.
# @arg $@ string Expected to be: <mode> <project-path> -- <command...>
# @stderr Validation error emitted via die when the shape is invalid.
# @exitcode 0 If the required separator and minimum argument count are present.
# @exitcode 1 If the command does not match the expected wrapper contract.
require_command_separator() {
    [[ $# -ge 3 ]] || die "expected: <mode> <project-path> -- <command...>"
    [[ "$3" == "--" ]] || die "expected command separator --"
}
