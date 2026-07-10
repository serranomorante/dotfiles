#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: pkm foam ai-autotrigger python
# dotfiles-test-case: foam-ai-autotrigger-syntax
# dotfiles-test-case: foam-ai-autotrigger-completes-new-syncthing-todo
# dotfiles-test-case: foam-ai-autotrigger-ignores-missing-id
# dotfiles-test-case: foam-ai-autotrigger-skips-local-reason
# dotfiles-test-case: foam-ai-autotrigger-records-wrapper-failure
# dotfiles-test-case: foam-ai-autotrigger-retries-failed-digest

# Purpose: Verify the dedicated Foam AI TODO parser without invoking real agents.

script_under_test="${DOTFILES_TEST_ROOT}/PKM/bin/foam-ai-autotrigger"

make_notes_root() {
    local notes_root="${DOTFILES_TEST_TMP}/notes"
    mkdir -p "${notes_root}/misc/todos"
    printf '%s\n' "$notes_root"
}

write_success_wrapper() {
    local wrapper="${DOTFILES_TEST_TMP}/wrapper-success"

    cat >"$wrapper" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

payload=$(cat)
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/wrapper.args"
printf '%s\n' "$payload" >"${DOTFILES_TEST_TMP}/wrapper.payload"
printf 'done\n'
BASH
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
}

write_failure_wrapper() {
    local wrapper="${DOTFILES_TEST_TMP}/wrapper-failure"

    cat >"$wrapper" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

cat >"${DOTFILES_TEST_TMP}/wrapper.payload"
printf 'agent failed intentionally\n' >&2
exit 23
BASH
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
}

write_todo_file() {
    local notes_root=$1
    shift
    printf '%s\n' "$@" >"${notes_root}/misc/todos/ai-autotrigger.todos.md"
}

run_parser() {
    local notes_root=$1
    local wrapper=$2
    shift 2

    "$script_under_test" run \
        --notes-root "$notes_root" \
        --state-dir "${DOTFILES_TEST_TMP}/state" \
        --wrapper "$wrapper" \
        "$@"
}

case "${DOTFILES_TEST_CASE:-}" in
foam-ai-autotrigger-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
foam-ai-autotrigger-completes-new-syncthing-todo)
    notes_root=$(make_notes_root)
    wrapper=$(write_success_wrapper)
    write_todo_file "$notes_root" \
        "# AI Autotrigger Todos" \
        "" \
        "- [ ] **Investigate the synced task**\\" \
        "  Use the phone-provided details." \
        "  @id phone-task-1" \
        "  @tags #autotrigger #music-production" \
        "  @agent claude" \
        "  @model sonnet" \
        "  @cwd ${notes_root}" \
        "  @timeout 30"

    run_parser "$notes_root" "$wrapper" --reason syncthing >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q '^- \[x\] \*\*Investigate the synced task\*\*\\$' "${notes_root}/misc/todos/ai-autotrigger.todos.md"
    rg -q '"status": "completed"' "${DOTFILES_TEST_TMP}/state/state.json"
    rg -q -- '--agent claude --input-json -' "${DOTFILES_TEST_TMP}/wrapper.args"
    python - "${DOTFILES_TEST_TMP}/wrapper.payload" "$notes_root" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
notes_root = sys.argv[2]
assert payload["schema"] == "foam-ai-autotrigger.v1"
assert payload["todo"]["id"] == "phone-task-1"
assert payload["todo"]["title"] == "Investigate the synced task"
assert payload["todo"]["tags"] == ["#autotrigger", "#music-production"]
assert payload["todo"]["body"] == "Use the phone-provided details."
assert payload["execution"]["agent"] == "claude"
assert payload["execution"]["model"] == "sonnet"
assert payload["execution"]["cwd"] == notes_root
assert payload["execution"]["timeout_seconds"] == "30"
PY
    ;;
foam-ai-autotrigger-ignores-missing-id)
    notes_root=$(make_notes_root)
    wrapper=$(write_success_wrapper)
    write_todo_file "$notes_root" \
        "# AI Autotrigger Todos" \
        "" \
        "- [ ] **No id task**\\" \
        "  This must not run." \
        "  @tags #autotrigger"

    run_parser "$notes_root" "$wrapper" --reason syncthing >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q '^- \[ \] \*\*No id task\*\*\\$' "${notes_root}/misc/todos/ai-autotrigger.todos.md"
    [[ ! -e "${DOTFILES_TEST_TMP}/wrapper.payload" ]]
    rg -q "without @id" "${DOTFILES_TEST_TMP}/stderr"
    ;;
foam-ai-autotrigger-skips-local-reason)
    notes_root=$(make_notes_root)
    wrapper=$(write_success_wrapper)
    write_todo_file "$notes_root" \
        "# AI Autotrigger Todos" \
        "" \
        "- [ ] **Local edit task**\\" \
        "  This must not run from local triggers." \
        "  @id local-task" \
        "  @tags #autotrigger"

    run_parser "$notes_root" "$wrapper" --reason local >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q '^- \[ \] \*\*Local edit task\*\*\\$' "${notes_root}/misc/todos/ai-autotrigger.todos.md"
    [[ ! -e "${DOTFILES_TEST_TMP}/wrapper.payload" ]]
    rg -q "skipping reason 'local'" "${DOTFILES_TEST_TMP}/stderr"
    ;;
foam-ai-autotrigger-records-wrapper-failure)
    notes_root=$(make_notes_root)
    wrapper=$(write_failure_wrapper)
    write_todo_file "$notes_root" \
        "# AI Autotrigger Todos" \
        "" \
        "- [ ] **Failing task**\\" \
        "  This wrapper returns a failure." \
        "  @id failing-task" \
        "  @tags #autotrigger"

    if run_parser "$notes_root" "$wrapper" --reason syncthing >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'parser unexpectedly succeeded\n' >&2
        exit 1
    fi

    rg -q '^- \[ \] \*\*Failing task\*\*\\$' "${notes_root}/misc/todos/ai-autotrigger.todos.md"
    rg -q '"status": "failed"' "${DOTFILES_TEST_TMP}/state/state.json"
    rg -q '"exit_code": 23' "${DOTFILES_TEST_TMP}/state/state.json"
    rg -q "agent failed intentionally" "${DOTFILES_TEST_TMP}/stderr"
    ;;
foam-ai-autotrigger-retries-failed-digest)
    notes_root=$(make_notes_root)
    failure_wrapper=$(write_failure_wrapper)
    success_wrapper=$(write_success_wrapper)
    write_todo_file "$notes_root" \
        "# AI Autotrigger Todos" \
        "" \
        "- [ ] **Retry failed task**\\" \
        "  The same digest previously failed and must be retried." \
        "  @id retry-task" \
        "  @tags #autotrigger"

    if run_parser "$notes_root" "$failure_wrapper" --reason syncthing >"${DOTFILES_TEST_TMP}/first.stdout" 2>"${DOTFILES_TEST_TMP}/first.stderr"; then
        printf 'first parser run unexpectedly succeeded\n' >&2
        exit 1
    fi
    rg -q '"status": "failed"' "${DOTFILES_TEST_TMP}/state/state.json"

    "$script_under_test" run \
        --notes-root "$notes_root" \
        --state-dir "${DOTFILES_TEST_TMP}/state" \
        --wrapper "$success_wrapper" \
        --reason syncthing >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q '^- \[x\] \*\*Retry failed task\*\*\\$' "${notes_root}/misc/todos/ai-autotrigger.todos.md"
    rg -q '"status": "completed"' "${DOTFILES_TEST_TMP}/state/state.json"
    rg -q '"retry-task"' "${DOTFILES_TEST_TMP}/wrapper.payload"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
