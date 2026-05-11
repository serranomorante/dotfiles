# Purpose: Generic Kitty window helpers shared across scripts in term/bin/ and
#   editor wrappers. Source from POSIX sh.
# Scope: Targets the current Kitty instance's focused OS window via the
#   ambient `kitten @` socket. Cross-socket matching (multiple kitty
#   instances, cwd-based focus, etc.) lives in `kitty-dmenu-common.bash` and
#   uses `kitten @ --to "unix:$socket"`.
# Notes: Functions are stateless and only depend on `kitten` for remote
#   control. `kitty_target_window_id` additionally needs `jq` for the JSON
#   fallback. App-specific focus helpers belong to the owning script, not here.

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
