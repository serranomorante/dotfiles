#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: term
# dotfiles-test-tags: term tmux copy-mark
# dotfiles-test-case: tmux-copy-mark-save-writes-state-file
# dotfiles-test-case: tmux-copy-mark-record-entry-hydrates-pool
# dotfiles-test-case: tmux-copy-mark-restore-loads-persisted-mark
# dotfiles-test-case: tmux-copy-mark-missing-mark-is-noop
# dotfiles-test-case: tmux-copy-mark-survives-server-restart
# dotfiles-test-case: tmux-copy-mark-save-last-does-not-persist

# Purpose: Verify tmux copy marks persist to the state pool and hydrate into
# fresh panes after a tmux server restart.

mark_script="${DOTFILES_TEST_ROOT}/term/bin/tmux-copy-mark"
sock="${DOTFILES_TEST_TMP}/tmux.sock"
state="${XDG_STATE_HOME:-${DOTFILES_TEST_TMP}/xdg-state}/dotfiles/tmux-copy-mark/state"

start_server() {
    tmux -f /dev/null -S "$sock" new-session -d -x 80 -y 24 -s tmux-copy-mark-test
}

stop_server() {
    tmux -S "$sock" kill-server 2>/dev/null || true
}

pane_id() {
    tmux -S "$sock" display-message -p -t tmux-copy-mark-test '#{pane_id}'
}

pane_in_mode() {
    tmux -S "$sock" display-message -p -t "$1" '#{pane_in_mode}'
}

pane_option() {
    tmux -S "$sock" display-message -p -t "$1" "#{@$2}"
}

write_pool() {
    mkdir -p "$(dirname "$state")"
    printf '%s\n' "$@" >"$state"
}

case "${DOTFILES_TEST_CASE:-}" in
tmux-copy-mark-save-writes-state-file)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save "$sock" "$P" a
    [ -f "$state" ]
    for field in scroll-position cursor-x cursor-y position-limit; do
        rg -q "^@dotfiles-copy-mark-a-${field}=[0-9]+$" "$state"
    done
    stop_server
    ;;
tmux-copy-mark-record-entry-hydrates-pool)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    write_pool '@dotfiles-copy-mark-b-scroll-position=77'
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" record-entry "$sock" "$P"
    [ "$(pane_option "$P" dotfiles-copy-mark-b-scroll-position)" = 77 ]
    write_pool '@dotfiles-copy-mark-b-scroll-position=99'
    "$mark_script" record-entry "$sock" "$P"
    [ "$(pane_option "$P" dotfiles-copy-mark-b-scroll-position)" = 77 ]
    stop_server
    ;;
tmux-copy-mark-restore-loads-persisted-mark)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    write_pool \
        '@dotfiles-copy-mark-c-scroll-position=5' \
        '@dotfiles-copy-mark-c-cursor-x=2' \
        '@dotfiles-copy-mark-c-cursor-y=3'
    "$mark_script" restore "$sock" "$P" c
    [ "$(pane_in_mode "$P")" = 1 ]
    [ "$(pane_option "$P" dotfiles-copy-mark-c-scroll-position)" = 5 ]
    stop_server
    ;;
tmux-copy-mark-missing-mark-is-noop)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    "$mark_script" restore "$sock" "$P" z
    [ "$(pane_in_mode "$P")" = 0 ]
    [ -z "$(pane_option "$P" dotfiles-copy-mark-z-scroll-position)" ]
    stop_server
    ;;
tmux-copy-mark-survives-server-restart)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save "$sock" "$P" a
    [ -f "$state" ]
    stop_server
    rm -f "$sock"
    start_server
    P2=$(pane_id)
    "$mark_script" record-entry "$sock" "$P2"
    [ -n "$(pane_option "$P2" dotfiles-copy-mark-a-scroll-position)" ]
    "$mark_script" restore "$sock" "$P2" a
    [ "$(pane_in_mode "$P2")" = 1 ]
    stop_server
    ;;
tmux-copy-mark-save-last-does-not-persist)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save-last-and-cancel "$sock" "$P"
    [ ! -e "$state" ]
    stop_server
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
