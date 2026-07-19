#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: agent-session-store e2e codex
# dotfiles-test-case: agent-session-store-current-id-prefers-history-over-newer-cwd-session
# dotfiles-test-case: agent-session-store-refresh-limits-old-sessions
# dotfiles-test-case: agent-session-store-watch-new-ignores-stale-unknown-sessions

# Purpose: Exercise the agent-session-store CLI against realistic transcript files.

store="${DOTFILES_TEST_ROOT}/utilities/bin/agent-session-store"
export DOTFILES_AGENT_SESSION_STORE_SOURCE_DIR="${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/agent-session-store"

write_codex_session() {
    local path=$1
    local id=$2
    local cwd=$3
    local timestamp=$4
    local title=$5

    mkdir -p "$(dirname "$path")"
    cat >"$path" <<EOF
{"type":"session_meta","payload":{"id":"${id}","cwd":"${cwd}","timestamp":"${timestamp}","originator":"codex-tui"}}
{"type":"event_msg","payload":{"type":"user_message","message":"${title}"}}
EOF
}

append_json_id() {
    local id=$1
    if [[ "$known_json" != "[" ]]; then
        known_json="${known_json},"
    fi
    known_json="${known_json}\"${id}\""
}

case "${DOTFILES_TEST_CASE:-}" in
agent-session-store-current-id-prefers-history-over-newer-cwd-session)
    root="${DOTFILES_TEST_TMP}/codex-sessions"
    history="${DOTFILES_TEST_TMP}/codex-history.jsonl"
    cwd="${DOTFILES_TEST_TMP}/repo"
    playbook_id="019f6b4d-playbook"
    elasticsearch_id="019f6b4d-elasticsearch"
    mkdir -p "$cwd"

    write_codex_session "${root}/2026/07/16/playbook.jsonl" "$playbook_id" "$cwd" "2026-07-16T14:10:00.000Z" "Fix unsigned linux-rt playbook failure"
    write_codex_session "${root}/2026/07/16/elasticsearch.jsonl" "$elasticsearch_id" "$cwd" "2026-07-16T14:00:00.000Z" "Investigate Elasticsearch snapshot failure"
    touch -d "2026-07-16 14:10:00 UTC" "${root}/2026/07/16/playbook.jsonl"
    touch -d "2026-07-16 14:30:00 UTC" "${root}/2026/07/16/elasticsearch.jsonl"

    printf '{"session_id":"%s"}\n' "$playbook_id" >"$history"

    resolved=$("$store" --provider codex --root "$root" current-id --cwd "$cwd" --history "$history")
    if [[ "$resolved" != "$playbook_id" ]]; then
        printf 'expected current-id to use history session %s, got %s\n' "$playbook_id" "$resolved" >&2
        exit 1
    fi

    ids_json=$("$store" --provider codex --root "$root" ids "$cwd")
    if [[ "$ids_json" != *"$playbook_id"* || "$ids_json" != *"$elasticsearch_id"* ]]; then
        printf 'expected ids output to include both cwd sessions, got: %s\n' "$ids_json" >&2
        exit 1
    fi
    ;;
agent-session-store-refresh-limits-old-sessions)
    root="${DOTFILES_TEST_TMP}/codex-sessions"
    cwd="${DOTFILES_TEST_TMP}/repo"
    mkdir -p "$cwd"

    for i in $(seq 1 200); do
        printf -v ordinal '%03d' "$i"
        id="session-${ordinal}"
        path="${root}/2026/07/18/session-${ordinal}.jsonl"
        write_codex_session "$path" "$id" "$cwd" "2026-07-18T10:00:00.000Z" "Refresh session ${ordinal}"
        touch -d "@$((1800000000 + i))" "$path"
    done

    refresh_json=$("$store" --provider codex --root "$root" refresh)
    if [[ "$refresh_json" == *'"id":"session-001"'* ]]; then
        printf 'expected refresh to omit stale sessions, got: %s\n' "$refresh_json" >&2
        exit 1
    fi
    if [[ "$refresh_json" != *'"id":"session-200"'* ]]; then
        printf 'expected refresh to include newest sessions, got: %s\n' "$refresh_json" >&2
        exit 1
    fi
    ;;
agent-session-store-watch-new-ignores-stale-unknown-sessions)
    root="${DOTFILES_TEST_TMP}/codex-sessions"
    cwd="${DOTFILES_TEST_TMP}/repo"
    mkdir -p "$cwd"

    known_json="["
    for i in $(seq 1 100); do
        printf -v ordinal '%03d' "$i"
        id="old-${ordinal}"
        path="${root}/2026/07/18/session-${ordinal}.jsonl"
        write_codex_session "$path" "$id" "$cwd" "2026-07-18T10:00:00.000Z" "Old session ${ordinal}"
        touch -d "@$((1800000000 + i))" "$path"
        if (( i > 20 )); then
            append_json_id "$id"
        fi
    done
    known_json="${known_json}]"

    timeout_json=$("$store" --provider codex --root "$root" watch-new "$cwd" "$known_json" 0.05 0.01 0.01)
    if [[ "$timeout_json" != *'"event":"timeout"'* ]]; then
        printf 'expected watch-new to ignore stale unknown sessions, got: %s\n' "$timeout_json" >&2
        exit 1
    fi

    new_id="new-session"
    new_path="${root}/2026/07/19/new.jsonl"
    write_codex_session "$new_path" "$new_id" "$cwd" "2026-07-19T12:00:00.000Z" "Investigate new Codex session"
    touch -d "@1800000200" "$new_path"

    watch_json=$("$store" --provider codex --root "$root" watch-new "$cwd" "$known_json" 1 0.05 0.05)
    if [[ "$watch_json" != *'"event":"session"'* || "$watch_json" != *"\"id\":\"${new_id}\""* ]]; then
        printf 'expected watch-new to find newest session %s, got: %s\n' "$new_id" "$watch_json" >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
