#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: promnesia agent-conversations
# dotfiles-test-readonly: /home/aaaa/data/apps/PKM/.venv
# dotfiles-test-case: agent-conversations-extracts-links

# Purpose: Verify the promnesia agent-conversations source extracts referenced
# links (with title, session id and a conversation editor link) from claude,
# codex, gemini and opencode transcripts.

source_module="${DOTFILES_TEST_ROOT}/PKM/dot-config/promnesia/agent_conversations.py"
venv_python=/home/aaaa/data/apps/PKM/.venv/bin/python

write_claude_fixture() {
    local dir=$1
    mkdir -p "$dir/-proj"
    cat >"$dir/-proj/claude-session-1.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"investigate https://example.org/foo for the new page"},"sessionId":"claude-session-1","cwd":"/repo/claude","timestamp":"2026-07-16T14:10:00.000Z"}
{"type":"summary","aiTitle":"Investigate foo","sessionId":"claude-session-1","cwd":"/repo/claude","timestamp":"2026-07-16T14:12:00.000Z"}
EOF
}

write_codex_fixture() {
    local dir=$1
    mkdir -p "$dir/2026/07/16"
    cat >"$dir/2026/07/16/rollout-019ec503.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"019ec503","cwd":"/repo/codex","timestamp":"2026-07-16T14:10:00.000Z","thread_source":"user"}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"fix the login page, see https://example.com/login"}]}}
EOF
}

write_gemini_fixture() {
    local dir=$1
    mkdir -p "$dir/proj/chats"
    printf '%s\n' '/repo/gemini' >"$dir/proj/.project_root"
    cat >"$dir/proj/chats/session-2026-07-16-gem1.json" <<'EOF'
{"sessionId":"gemini-session-1","projectHash":"x","startTime":"2026-07-16T14:10:00.000Z","lastUpdated":"2026-07-16T14:20:00.000Z","messages":[{"id":"m1","timestamp":"2026-07-16T14:10:00.000Z","type":"user","content":"check https://gemini.example.com/page"},{"id":"m2","type":"gemini","content":"will do"}]}
EOF
}

write_opencode_fixture() {
    local db=$1
    mkdir -p "$(dirname "$db")"
    python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
con = sqlite3.connect(db)
con.executescript(
    """
    CREATE TABLE session (
        id TEXT PRIMARY KEY, project_id TEXT, slug TEXT, directory TEXT,
        title TEXT, version TEXT, time_created INTEGER, time_updated INTEGER
    );
    CREATE TABLE part (
        id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT,
        time_created INTEGER, time_updated INTEGER, data TEXT
    );
    INSERT INTO session VALUES (
        'ses_test123', 'p', 'slug', '/repo/opencode', 'OpenCode session title',
        '1', 1786810608066, 1786817169037
    );
    INSERT INTO part VALUES (
        'prt_1', 'm1', 'ses_test123', 1786810608066, 1786810608066,
        '{"type":"text","text":"see https://opencode.example.com/doc"}'
    );
    """
)
con.commit()
con.close()
PY
}

run_source() {
    local root=$1
    "$venv_python" - "$source_module" "$root" <<'PY'
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("agent_conversations", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules["agent_conversations"] = module
spec.loader.exec_module(module)

for visit in module.index(sys.argv[2]):
    if isinstance(visit, Exception):
        print(f"EXCEPTION {type(visit).__name__}: {visit}", file=sys.stderr)
        sys.exit(2)
    print(json.dumps({
        "url": visit.url,
        "title": visit.locator.title,
        "href": visit.locator.href,
        "context": visit.context,
    }))
PY
}

case "${DOTFILES_TEST_CASE:-}" in
agent-conversations-extracts-links)
    root="${DOTFILES_TEST_TMP}/conversations"
    mkdir -p "$root"

    write_claude_fixture "$root/.claude/projects"
    write_codex_fixture "$root/.codex/sessions"
    write_gemini_fixture "$root/.gemini/tmp"
    write_opencode_fixture "$root/.local/share/opencode/opencode.db"

    out="${DOTFILES_TEST_TMP}/visits.jsonl"
    run_source "$root/.claude/projects" >"$out"
    run_source "$root/.codex/sessions" >>"$out"
    run_source "$root/.gemini/tmp" >>"$out"
    run_source "$root/.local/share/opencode" >>"$out"

    rg -q 'https://example.org/foo' "$out"
    rg -q '"title": "claude: Investigate foo"' "$out"
    rg -q 'editor:///agent_conversation/repo/claude/claude-session-1' "$out"

    rg -q 'https://example.com/login' "$out"
    rg -q '"title": "codex: fix the login page' "$out"
    rg -q 'editor:///agent_conversation/repo/codex/019ec503' "$out"

    rg -q 'https://gemini.example.com/page' "$out"
    rg -q '"title": "gemini: check https://gemini' "$out"
    rg -q 'editor:///agent_conversation/repo/gemini/gemini-session-1' "$out"

    rg -q 'https://opencode.example.com/doc' "$out"
    rg -q '"title": "opencode: OpenCode session title"' "$out"
    rg -q 'editor:///agent_conversation/repo/opencode/ses_test123' "$out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
