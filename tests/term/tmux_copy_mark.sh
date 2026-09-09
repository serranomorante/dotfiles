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
# dotfiles-test-case: tmux-copy-mark-per-session-isolation
# dotfiles-test-case: tmux-copy-mark-list-lists-saved-marks
# dotfiles-test-case: tmux-copy-mark-save-stores-snippet
# dotfiles-test-case: tmux-copy-mark-label-sets-label
# dotfiles-test-case: tmux-copy-mark-save-prompt-labels-pane-id-one

# Purpose: Verify tmux copy marks persist per session, hydrate into fresh panes
# after a tmux server restart, and list through the list action.

mark_script="${DOTFILES_TEST_ROOT}/term/bin/tmux-copy-mark"
sock="${DOTFILES_TEST_TMP}/tmux.sock"
session="tmux-copy-mark-test"
state_dir="${XDG_STATE_HOME:-${DOTFILES_TEST_TMP}/xdg-state}/dotfiles/tmux-copy-mark"
state="${state_dir}/state-${session}"
labels_dir="${XDG_STATE_HOME:-${DOTFILES_TEST_TMP}/xdg-state}/dotfiles/marks"
labels="${labels_dir}/${session}.labels"

start_server() {
    tmux -f /dev/null -S "$sock" new-session -d -x 80 -y 24 -s "$session"
}

stop_server() {
    tmux -S "$sock" kill-server 2>/dev/null || true
}

pane_of() {
    tmux -S "$sock" display-message -p -t "$1" '#{pane_id}'
}

pane_id() {
    pane_of "$session"
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

host_sock="${DOTFILES_TEST_TMP}/tmux-host.sock"

# `command-prompt` is a no-op without an attached client, so the prompt path is
# driven through a client hosted in a second tmux server. The host pane renders
# everything that client shows, including the prompt, so it can be both the
# keyboard and the readiness signal for the prompt itself.
start_host_client() {
    tmux -f /dev/null -S "$host_sock" new-session -d -x 100 -y 30 -s host \
        "tmux -S '$sock' attach-session -t '$session'"
    wait_for_attached_client
}

stop_host_client() {
    tmux -S "$host_sock" kill-server 2>/dev/null || true
}

wait_for_attached_client() {
    local tries=100
    until [ -n "$(tmux -S "$sock" list-clients -F '#{client_name}' 2>/dev/null)" ]; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
            printf 'no client attached to %s\n' "$session" >&2
            return 1
        fi
        sleep 0.1
    done
}

wait_for_host_text() {
    local needle=$1 tries=100
    until tmux -S "$host_sock" capture-pane -p -t host 2>/dev/null | grep -Fq "$needle"; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
            printf 'host pane never showed: %s\n' "$needle" >&2
            return 1
        fi
        sleep 0.1
    done
}

wait_for_label() {
    local value=$1 tries=100
    until [ -f "$labels" ] && grep -Fqx "a-label=${value}" "$labels"; do
        tries=$((tries - 1))
        if [ "$tries" -le 0 ]; then
            printf 'label never stored: %s\n' "$value" >&2
            return 1
        fi
        sleep 0.1
    done
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
tmux-copy-mark-per-session-isolation)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    tmux -f /dev/null -S "$sock" new-session -d -x 80 -y 24 -s 'beta one'
    P=$(pane_id)
    Q=$(pane_of 'beta one')
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save "$sock" "$P" a
    tmux -S "$sock" copy-mode -t "$Q"
    "$mark_script" save "$sock" "$Q" b

    [ -f "$state" ]
    [ -f "${state_dir}/state-beta_one" ]
    refute test -e "${state_dir}/state"

    rg -q '^@dotfiles-copy-mark-a-scroll-position=' "$state"
    refute rg -q '^@dotfiles-copy-mark-b-scroll-position=' "$state"
    rg -q '^@dotfiles-copy-mark-b-scroll-position=' "${state_dir}/state-beta_one"
    refute rg -q '^@dotfiles-copy-mark-a-scroll-position=' "${state_dir}/state-beta_one"
    stop_server
    ;;
tmux-copy-mark-list-lists-saved-marks)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    write_pool \
        '@dotfiles-copy-mark-b-scroll-position=77' \
        '@dotfiles-copy-mark-m-scroll-position=7'
    "$mark_script" list "$sock" "$P" >"${DOTFILES_TEST_TMP}/out"
    grep -qx 'b' "${DOTFILES_TEST_TMP}/out"
    grep -qx 'm' "${DOTFILES_TEST_TMP}/out"
    refute grep -qx 'a' "${DOTFILES_TEST_TMP}/out"
    stop_server
    ;;
tmux-copy-mark-save-stores-snippet)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    tmux -S "$sock" send-keys -t "$P" 'echo SNIPPET-LINE-42' Enter
    sleep 1
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save "$sock" "$P" a
    [ -f "$labels" ]
    rg -q '^a-snippet=.+$' "$labels"
    stop_server
    ;;
tmux-copy-mark-label-sets-label)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    start_server
    P=$(pane_id)
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save "$sock" "$P" a
    "$mark_script" label "$sock" "$P" a 'my loop title'
    rg -q '^a-label=my loop title$' "$labels"
    "$mark_script" list "$sock" "$P" >"${DOTFILES_TEST_TMP}/out"
    grep -qx 'a my loop title' "${DOTFILES_TEST_TMP}/out"
    stop_server
    ;;
tmux-copy-mark-save-prompt-labels-pane-id-one)
    export XDG_STATE_HOME="${DOTFILES_TEST_TMP}/xdg-state"
    # `command-prompt` replaces `%1` in its callback template with the typed
    # answer, so a pane id interpolated into that template used to be clobbered
    # by the label itself. Burn `%0` on a throwaway session so the marked pane
    # really is `%1` and the regression can reappear.
    tmux -f /dev/null -S "$sock" new-session -d -x 80 -y 24 -s burn-pane-zero
    start_server
    P=$(pane_id)
    [ "$P" = '%1' ]

    start_host_client
    tmux -S "$sock" copy-mode -t "$P"
    "$mark_script" save-prompt "$sock" "$P" a &
    prompt_pid=$!
    wait_for_host_text 'mark label (optional):'
    tmux -S "$host_sock" send-keys -t host 'pane one label'
    tmux -S "$host_sock" send-keys -t host Enter
    wait "$prompt_pid"

    wait_for_label 'pane one label'
    # An unresolvable session scope would land in the shared empty-scope file.
    refute test -e "${labels_dir}/.labels"
    stop_host_client
    stop_server
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
