# Purpose: Shared cache and Kitty remote-control helpers for kitty-dmenu scripts.
# Notes: Source from Bash. Cached values are short-lived and always rebuildable.

KITTY_DMENU_CACHE_NAMESPACE=${KITTY_DMENU_CACHE_NAMESPACE:-kitty-dmenu}
KITTY_DMENU_SOCKET_CACHE_KEY=${KITTY_DMENU_SOCKET_CACHE_KEY:-sockets-v1}
KITTY_DMENU_SOCKET_CACHE_TTL=${KITTY_DMENU_SOCKET_CACHE_TTL:-10}
KITTY_DMENU_WINDOW_CACHE_KEY=${KITTY_DMENU_WINDOW_CACHE_KEY:-open-cwds-v1}
# Keep the last open-cwd list for fast startup; fzf's one-shot refresh owns freshness.
KITTY_DMENU_WINDOW_CACHE_TTL=${KITTY_DMENU_WINDOW_CACHE_TTL:-604800}

kitty_dmenu_cachectl_bin() {
    if [[ -n ${KITTY_DMENU_CACHECTL_BIN:-} && -x ${KITTY_DMENU_CACHECTL_BIN:-} ]]; then
        printf '%s\n' "$KITTY_DMENU_CACHECTL_BIN"
        return 0
    fi

    if [[ -x $HOME/dotfiles/utilities/bin/cachectl ]]; then
        printf '%s\n' "$HOME/dotfiles/utilities/bin/cachectl"
        return 0
    fi

    command -v cachectl 2>/dev/null
}

kitty_dmenu_cache_get() {
    local key=$1
    local cachectl_bin

    cachectl_bin=$(kitty_dmenu_cachectl_bin) || return 1
    "$cachectl_bin" get "$KITTY_DMENU_CACHE_NAMESPACE" "$key" 2>/dev/null
}

kitty_dmenu_cache_set() {
    local key=$1
    local ttl=$2
    local cachectl_bin

    cachectl_bin=$(kitty_dmenu_cachectl_bin) || return 0
    "$cachectl_bin" set "$KITTY_DMENU_CACHE_NAMESPACE" "$key" "$ttl" >/dev/null 2>&1
}

kitty_dmenu_cache_del() {
    local key=$1
    local cachectl_bin

    cachectl_bin=$(kitty_dmenu_cachectl_bin) || return 0
    "$cachectl_bin" del "$KITTY_DMENU_CACHE_NAMESPACE" "$key" >/dev/null 2>&1
}

kitty_dmenu_discover_sockets() {
    if command -v ss >/dev/null 2>&1; then
        ss -xlH 2>/dev/null | awk '
            {
                line = $0
                while (match(line, /@kitty(-[0-9]+)?/)) {
                    print substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        '
    fi

    if command -v lsof >/dev/null 2>&1; then
        lsof -U 2>/dev/null | awk '
            {
                line = $0
                while (match(line, /@kitty(-[0-9]+)?/)) {
                    print substr(line, RSTART, RLENGTH)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
        '
    fi
}

kitty_dmenu_socket_list() {
    local force_refresh=${1:-0}
    local cached sockets

    if [[ $force_refresh != 1 ]]; then
        if cached=$(kitty_dmenu_cache_get "$KITTY_DMENU_SOCKET_CACHE_KEY") && [[ -n $cached ]]; then
            printf '%s\n' "$cached"
            return 0
        fi
    fi

    sockets=$(kitty_dmenu_discover_sockets | sort -u)
    if [[ -n $sockets ]]; then
        printf '%s\n' "$sockets" | kitty_dmenu_cache_set "$KITTY_DMENU_SOCKET_CACHE_KEY" "$KITTY_DMENU_SOCKET_CACHE_TTL"
        printf '%s\n' "$sockets"
    elif [[ $force_refresh == 1 ]]; then
        kitty_dmenu_cache_del "$KITTY_DMENU_SOCKET_CACHE_KEY"
    fi
}

kitty_dmenu_regex_escape() {
    sed 's/[][\\.^$*+?{}()|]/\\&/g' <<<"$1"
}

kitty_dmenu_shell_quote() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

kitty_dmenu_fzf_reload() {
    local fzf_sock=$1
    local choices_file=$2
    local payload

    [[ -S $fzf_sock ]] || return 1
    command -v curl >/dev/null 2>&1 || return 1

    payload="reload(cat $(kitty_dmenu_shell_quote "$choices_file"))"
    curl -fsS --unix-socket "$fzf_sock" http://fzf -d "$payload" >/dev/null 2>&1
}

kitty_dmenu_wait_for_fzf_socket() {
    local fzf_sock=$1
    local attempts=${2:-40}

    while ((attempts > 0)); do
        [[ -S $fzf_sock ]] && return 0
        sleep 0.05 || return 1
        attempts=$((attempts - 1))
    done

    return 1
}

kitty_dmenu_fzf_refresh_once() {
    local choices_file=$1
    local fzf_sock=$2
    local refresh_function=$3
    shift 3

    local next_file
    next_file=$choices_file.next

    if "$refresh_function" "$@" >"$next_file" 2>/dev/null; then
        if cmp -s "$choices_file" "$next_file"; then
            rm -f "$next_file"
            return 0
        fi

        mv -f "$next_file" "$choices_file"
        kitty_dmenu_wait_for_fzf_socket "$fzf_sock" && kitty_dmenu_fzf_reload "$fzf_sock" "$choices_file"
    else
        rm -f "$next_file"
    fi
}

kitty_dmenu_run_refreshing_fzf() {
    local choices_file=$1
    local selected_file=$2
    local prompt=$3
    local refresh_function=$4
    shift 4

    local fzf_sock refresh_pid status quoted_choices

    if ! command -v curl >/dev/null 2>&1; then
        fzf --prompt="$prompt" <"$choices_file" >"$selected_file"
        return $?
    fi

    fzf_sock=$choices_file.fzf.sock
    rm -f "$fzf_sock"
    quoted_choices=$(kitty_dmenu_shell_quote "$choices_file")

    kitty_dmenu_fzf_refresh_once "$choices_file" "$fzf_sock" "$refresh_function" "$@" &
    refresh_pid=$!

    FZF_API_KEY= fzf \
        --prompt="$prompt" \
        --listen="$fzf_sock" \
        --delimiter=$'\t' \
        --bind "ctrl-r:reload(cat $quoted_choices)" \
        <"$choices_file" >"$selected_file"
    status=$?

    kill "$refresh_pid" 2>/dev/null || true
    wait "$refresh_pid" 2>/dev/null || true
    rm -f "$fzf_sock"

    return "$status"
}

kitty_dmenu_focus_cwd_on_sockets() {
    local selected_path=$1
    shift

    local selected_regex socket error_msg
    selected_regex=$(kitty_dmenu_regex_escape "$selected_path")

    for socket in "$@"; do
        [[ -n $socket ]] || continue

        if error_msg=$(kitten @ --to "unix:$socket" focus-window --match "cwd:^${selected_regex}$" 2>&1); then
            return 0
        fi

        case $error_msg in
        *"No matching windows for expression"* | *"Failed to connect"* | *"Connection refused"* | *"connection refused"*)
            ;;
        *)
            notify-send "Error: $error_msg"
            ;;
        esac
    done

    return 1
}

kitty_dmenu_focus_cwd() {
    local selected_path=$1
    local sockets=()

    readarray -t sockets < <(kitty_dmenu_socket_list)
    if kitty_dmenu_focus_cwd_on_sockets "$selected_path" "${sockets[@]}"; then
        return 0
    fi

    readarray -t sockets < <(kitty_dmenu_socket_list 1)
    kitty_dmenu_focus_cwd_on_sockets "$selected_path" "${sockets[@]}"
}

kitty_dmenu_collect_window_entries() {
    local sockets=("$@")
    local tmpdir pid socket index file
    local pids=()

    ((${#sockets[@]} > 0)) || return 0

    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/kitty-dmenu-open.XXXXXX") || return 1

    index=0
    for socket in "${sockets[@]}"; do
        [[ -n $socket ]] || continue
        file=$tmpdir/$index.tsv
        index=$((index + 1))
        (
            kitten @ --to "unix:$socket" ls 2>/dev/null |
                jq -r --arg socket "$socket" '
                    .[]?.tabs[]?.windows[]?
                    | select(.cwd != null and .cwd != "")
                    | [.cwd, $socket]
                    | @tsv
                ' >"$file"
        ) &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    awk -F '\t' 'NF >= 2 && $1 != "" && !seen[$1]++ { print $1 "\t" $2 }' "$tmpdir"/*.tsv 2>/dev/null
    rm -rf "$tmpdir"
}

kitty_dmenu_open_cwd_choices() {
    local entries_file=$1
    local next_entries_file

    next_entries_file=$entries_file.next
    kitty_dmenu_window_entries 1 >"$next_entries_file"
    mv -f "$next_entries_file" "$entries_file"
    awk -F '\t' '{ print $1 }' "$entries_file"
}

kitty_dmenu_cached_window_entries() {
    kitty_dmenu_cache_get "$KITTY_DMENU_WINDOW_CACHE_KEY" || true
}

kitty_dmenu_window_entries() {
    local force_refresh=${1:-0}
    local cached entries
    local sockets=()

    if [[ $force_refresh != 1 ]]; then
        if cached=$(kitty_dmenu_cache_get "$KITTY_DMENU_WINDOW_CACHE_KEY") && [[ -n $cached ]]; then
            printf '%s\n' "$cached"
            return 0
        fi
    fi

    readarray -t sockets < <(kitty_dmenu_socket_list "$force_refresh")
    entries=$(kitty_dmenu_collect_window_entries "${sockets[@]}")

    if [[ -z $entries && $force_refresh != 1 ]]; then
        readarray -t sockets < <(kitty_dmenu_socket_list 1)
        entries=$(kitty_dmenu_collect_window_entries "${sockets[@]}")
    fi

    if [[ -n $entries ]]; then
        printf '%s\n' "$entries" | kitty_dmenu_cache_set "$KITTY_DMENU_WINDOW_CACHE_KEY" "$KITTY_DMENU_WINDOW_CACHE_TTL"
        printf '%s\n' "$entries"
    elif [[ $force_refresh == 1 ]]; then
        kitty_dmenu_cache_del "$KITTY_DMENU_WINDOW_CACHE_KEY"
    fi
}
