#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: pkm remind agent python
# dotfiles-test-case: foam-remind-agent-run-syntax
# dotfiles-test-case: foam-remind-agent-run-writes-result-and-payload
# dotfiles-test-case: foam-remind-agent-run-keeps-default-cwd
# dotfiles-test-case: foam-remind-agent-run-ignores-example-source-duplicates
# dotfiles-test-case: foam-remind-agent-run-fails-on-duplicate-id

# Purpose: Verify the Remind-to-agent helper without invoking a real agent.

script_under_test="${DOTFILES_TEST_ROOT}/PKM/bin/foam-remind-agent-run"

make_foam() {
    local notes="${DOTFILES_TEST_TMP}/notes"
    mkdir -p "${notes}/misc/tasks"
    cat >"${notes}/misc/tasks/todos.sample.md" <<'MARKDOWN'
# Sample | TODOS

- [ ] **Review sample task**
  Summarize the sample input.
  @id todo-sample-agent-task
  @tags #sample
  @model gpt-test

  ```remind
  @run agent
  REM jun 1 2026 AT 10:00 UNTIL oct 1 2026 *3
  ```
MARKDOWN
    printf '%s\n' "$notes"
}

write_fake_wrapper() {
    local wrapper="${DOTFILES_TEST_TMP}/agent-local-execution"

    cat >"$wrapper" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/wrapper.args"
cat >"${DOTFILES_TEST_TMP}/wrapper.payload"
printf 'sample answer\n'
BASH
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
}

write_fake_notify() {
    local home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "${home}/bin"
    cat >"${home}/bin/notification-action" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/notification-action.args"
BASH
    chmod +x "${home}/bin/notification-action"
    printf '%s\n' "$home"
}

write_fake_systemd_run() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/systemd-run" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/systemd-run.args"
while [ "$#" -gt 0 ]; do
    case "$1" in
    --user | --collect)
        shift
        ;;
    --unit=*)
        shift
        ;;
    --unit)
        shift 2
        ;;
    --)
        shift
        break
        ;;
    -*)
        shift
        ;;
    *)
        break
        ;;
    esac
done
"$@"
BASH
    chmod +x "${bin}/systemd-run"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
foam-remind-agent-run-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
foam-remind-agent-run-writes-result-and-payload)
    notes=$(make_foam)
    wrapper=$(write_fake_wrapper)
    home=$(write_fake_notify)
    bin=$(write_fake_systemd_run)

    HOME="$home" \
        PATH="${bin}:/usr/bin:/bin" \
        FOAM_REMIND_NOTES_ROOT="$notes" \
        FOAM_REMIND_AGENT_OUTPUT_ROOT="${notes}/misc/agent-runs" \
        FOAM_REMIND_AGENT_WRAPPER="$wrapper" \
        "$script_under_test" todo-sample-agent-task >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q -- '--agent codex --input-json -' "${DOTFILES_TEST_TMP}/wrapper.args"
    python - "${DOTFILES_TEST_TMP}/wrapper.payload" "$notes" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
notes = sys.argv[2]
assert payload["schema"] == "foam-ai-autotrigger.v1"
assert payload["todo"]["id"] == "todo-sample-agent-task"
assert payload["todo"]["title"] == "Review sample task"
assert payload["todo"]["body"] == "Summarize the sample input."
assert payload["todo"]["tags"] == ["#sample"]
assert payload["execution"]["agent"] == "codex"
assert payload["execution"]["model"] == "gpt-test"
assert payload["execution"]["cwd"] == notes
assert payload["source"]["relative_file"] == "misc/tasks/todos.sample.md"
PY
    result=$(find "${notes}/misc/agent-runs" -type f -name 'todo-sample-agent-task-*.md' -print -quit)
    [[ -n "$result" ]]
    rg -q "source: \\[\\[todos.sample#\\^todo-sample-agent-task\\]\\]" "$result"
    rg -q "status: completed" "$result"
    rg -q "sample answer" "$result"
    rg -q -- '^--user$' "${DOTFILES_TEST_TMP}/systemd-run.args"
    rg -q -- '^--collect$' "${DOTFILES_TEST_TMP}/systemd-run.args"
    rg -q -- '^--unit=notification-action-todo-sample-agent-task-' "${DOTFILES_TEST_TMP}/systemd-run.args"
    for _ in {1..20}; do
        [[ -e "${DOTFILES_TEST_TMP}/notification-action.args" ]] && break
        sleep 0.05
    done
    rg -q -- '^send$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q -- '^--summary$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q -- '^Agent TODO completed$' "${DOTFILES_TEST_TMP}/notification-action.args"
    python - "${DOTFILES_TEST_TMP}/notification-action.args" "$notes" <<'PY'
import json
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
payload = json.loads(lines[-1])
assert payload == {
    "schema": "dotfiles.notification-action.v1",
    "action": "open-foam-block-section",
    "cwd": sys.argv[2],
    "foam-section-id": "todo-sample-agent-task",
}
PY
    ;;
foam-remind-agent-run-keeps-default-cwd)
    notes=$(make_foam)
    wrapper=$(write_fake_wrapper)
    home=$(write_fake_notify)
    bin=$(write_fake_systemd_run)
    cat >>"${notes}/misc/tasks/todos.sample.md" <<'MARKDOWN'

- [ ] **Review dotfiles task**
  Trabaja en `~/dotfiles` y sigue su `AGENTS.md`.
  @id todo-dotfiles-agent-task
MARKDOWN

    HOME="$home" \
        PATH="${bin}:/usr/bin:/bin" \
        FOAM_REMIND_NOTES_ROOT="$notes" \
        FOAM_REMIND_AGENT_OUTPUT_ROOT="${notes}/misc/agent-runs" \
        FOAM_REMIND_AGENT_WRAPPER="$wrapper" \
        "$script_under_test" todo-dotfiles-agent-task >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    python - "${DOTFILES_TEST_TMP}/wrapper.payload" "$notes" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["todo"]["id"] == "todo-dotfiles-agent-task"
assert payload["execution"]["cwd"] == sys.argv[2]
assert payload["execution"]["sandbox"] == "workspace-write"
PY
    ;;
foam-remind-agent-run-ignores-example-source-duplicates)
    notes=$(make_foam)
    mkdir -p "${notes}/docs/agents" "${notes}/misc/agent-runs/2026-05"
    cat >"${notes}/docs/agents/remind-usage.md" <<'MARKDOWN'
# Remind usage

- [ ] **Example documentation task**
  @id todo-sample-agent-task
MARKDOWN
    cat >"${notes}/misc/agent-runs/2026-05/result.md" <<'MARKDOWN'
# Agent output

- [ ] **Generated output task**
  @id todo-sample-agent-task
MARKDOWN
    wrapper=$(write_fake_wrapper)
    home=$(write_fake_notify)
    bin=$(write_fake_systemd_run)

    HOME="$home" \
        PATH="${bin}:/usr/bin:/bin" \
        FOAM_REMIND_NOTES_ROOT="$notes" \
        FOAM_REMIND_AGENT_OUTPUT_ROOT="${notes}/misc/agent-runs" \
        FOAM_REMIND_AGENT_WRAPPER="$wrapper" \
        "$script_under_test" todo-sample-agent-task >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    python - "${DOTFILES_TEST_TMP}/wrapper.payload" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["source"]["relative_file"] == "misc/tasks/todos.sample.md"
assert payload["todo"]["title"] == "Review sample task"
PY
    ;;
foam-remind-agent-run-fails-on-duplicate-id)
    notes=$(make_foam)
    cat >>"${notes}/misc/tasks/todos.sample.md" <<'MARKDOWN'

- [ ] **duplicate**
  @id todo-sample-agent-task
MARKDOWN
    wrapper=$(write_fake_wrapper)
    home=$(write_fake_notify)

    if HOME="$home" PATH="/usr/bin:/bin" FOAM_REMIND_NOTES_ROOT="$notes" FOAM_REMIND_AGENT_WRAPPER="$wrapper" "$script_under_test" todo-sample-agent-task >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'helper unexpectedly accepted duplicate id\n' >&2
        exit 1
    fi
    rg -q "duplicate @id" "${DOTFILES_TEST_TMP}/stderr"
    [[ ! -e "${DOTFILES_TEST_TMP}/wrapper.payload" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
