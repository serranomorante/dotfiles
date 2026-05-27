# Purpose: Generic Kitty window helpers shared across scripts in term/bin/ and
#   editor wrappers. Source from POSIX sh.
# Scope: Owns predictable cwd-derived Kitty socket naming and helpers that
#   target the current Kitty instance's focused OS window via the ambient
#   `kitten @` socket.
# Notes: Functions are stateless and only depend on `kitten` for remote
#   control. `kitty_target_window_id` additionally needs `jq` for the JSON
#   fallback. App-specific focus helpers belong to the owning script, not here.

kitty_runtime_root() {
    printf '%s\n' "${XDG_RUNTIME_DIR:-"$HOME/.cache/nvim"}"
}

kitty_resolve_cwd() {
    cwd=${1:-}

    if [ -z "$cwd" ] || [ "$cwd" = "." ]; then
        cwd=${PWD:-}
    fi

    case $cwd in
    /*) ;;
    *)
        if resolved_cwd=$(cd "$cwd" 2>/dev/null && pwd); then
            cwd=$resolved_cwd
        elif [ -n "${PWD:-}" ]; then
            cwd=${PWD%/}/$cwd
        fi
        ;;
    esac

    case $cwd in
    /) printf '%s\n' / ;;
    *) printf '%s\n' "${cwd%/}" ;;
    esac
}

kitty_listen_on_from_pid() {
    kitty_pid=${1:-}

    case $kitty_pid in
    *[!0-9]* | "") return 1 ;;
    esac

    [ -r "/proc/$kitty_pid/environ" ] || return 1

    listen_on=$(
        tr '\0' '\n' <"/proc/$kitty_pid/environ" 2>/dev/null |
            sed -n 's/^KITTY_LISTEN_ON=//p' |
            sed -n '1p'
    )
    [ -n "$listen_on" ] || return 1
    printf '%s\n' "$listen_on"
}

kitty_nvim_servername_from_listen_on() {
    listen_on=${1:-}

    case $listen_on in
    unix:/*) socket=${listen_on#unix:} ;;
    *) return 1 ;;
    esac

    case $socket in
    */kitty-cwd-*.sock) printf '%s.nvim.sock\n' "${socket%.sock}" ;;
    *) return 1 ;;
    esac
}

kitty_nvim_servername_from_pid() {
    listen_on=$(kitty_listen_on_from_pid "${1:-}") || return 1
    kitty_nvim_servername_from_listen_on "$listen_on"
}

kitty_cwd_key() {
    cwd=${1%/}
    max_cwd_key_len=48

    if [ -z "$cwd" ] || [ "$cwd" = "/" ]; then
        cwd_key=root
    else
        cwd_key=${cwd#/}
        cwd_key=$(printf '%s' "$cwd_key" | sed 's|/|__|g' | tr -c 'A-Za-z0-9._-' '_')

        if [ ${#cwd_key} -gt "$max_cwd_key_len" ]; then
            if command -v sha256sum >/dev/null 2>&1; then
                cwd_hash=$(printf '%s' "$cwd" | sha256sum | cut -c 1-16)
            else
                cwd_hash=$(printf '%s' "$cwd" | cksum | sed 's/[[:space:]].*//')
            fi

            prefix_len=$((max_cwd_key_len - ${#cwd_hash} - 1))
            if [ "$prefix_len" -lt 1 ]; then
                printf '%s\n' "$cwd_hash"
                return 0
            fi

            cwd_prefix=$(printf '%s' "$cwd_key" | cut -c "1-${prefix_len}")
            cwd_key=${cwd_prefix}-${cwd_hash}
        fi
    fi

    printf '%s\n' "$cwd_key"
}

kitty_socket_for_cwd() {
    cwd=$(kitty_resolve_cwd "${1:-}") || return 1
    printf '%s/kitty-cwd-%s.sock\n' "$(kitty_runtime_root)" "$(kitty_cwd_key "$cwd")"
}

kitty_listen_on_for_cwd() {
    socket=$(kitty_socket_for_cwd "${1:-}") || return 1
    printf 'unix:%s\n' "$socket"
}

kitty_nvim_servername_from_cwd() {
    listen_on=$(kitty_listen_on_for_cwd "${1:-}") || return 1
    kitty_nvim_servername_from_listen_on "$listen_on"
}

kitty_nvim_servername_from_kitty_context() {
    kitty_nvim_servername_from_listen_on "${KITTY_LISTEN_ON:-}" ||
        kitty_nvim_servername_from_pid "${KITTY_PID:-}"
}

kitty_nvim_servername_from_context() {
    kitty_nvim_servername_from_kitty_context ||
        kitty_nvim_servername_from_cwd "${PWD:-}"
}

kitty_focus_match() {
    kitten @ focus-window --match "$1" >/dev/null 2>&1
}

kitty_focus_window_id() {
    [ -n "${1:-}" ] || return 1
    kitten @ focus-window --match "id:$1" >/dev/null 2>&1
}

kitty_focused_os_windows_json() {
    kitten @ ls --match state:focused_os_window 2>/dev/null
}

# kitty_target_window_id PROCESS_NAME
#
# Returns the id of a window in the focused OS window whose cmdline or
# foreground processes contain PROCESS_NAME. On ties, the more recently focused
# window wins.
kitty_target_window_id() {
    process_name=${1:-}

    command -v jq >/dev/null 2>&1 || return 1

    kitty_focused_os_windows_json | jq -r \
        --arg process_name "$process_name" '
      def argv_has_base($argv; $name):
        any(($argv // [])[]; (tostring | sub("^.*/"; "")) == $name);
      def foreground_has($w; $name):
        any(($w.foreground_processes // [])[]; argv_has_base(.cmdline; $name));
      def command_has($w; $name):
        $name != "" and (argv_has_base($w.cmdline; $name) or foreground_has($w; $name));
      def matches($w):
        command_has($w; $process_name);
      [
        .[]?.tabs[]?.windows[]? as $w
        | select(matches($w))
        | {
            id: $w.id,
            last_focused_at: ($w.last_focused_at // 0)
          }
      ]
      | sort_by(-(.last_focused_at))
      | .[0].id // empty
    '
}
