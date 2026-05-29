#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: pkm remind agent python
# dotfiles-test-case: foam-remind-agent-run-syntax
# dotfiles-test-case: foam-remind-agent-run-writes-result-and-payload
# dotfiles-test-case: foam-remind-agent-run-fails-on-duplicate-id

# Purpose: Verify the Remind-to-agent helper without invoking a real agent.

script_under_test="${DOTFILES_TEST_ROOT}/PKM/bin/foam-remind-agent-run"

make_foam() {
    local notes="${DOTFILES_TEST_TMP}/notes"
    mkdir -p "${notes}/misc/finance"
    cat >"${notes}/misc/finance/todos.finance.md" <<'MARKDOWN'
# Finance | TODOS

- [ ] **review the audio software deal**
  Check whether there is an official deal.
  @id todo-audio-software-deal
  @tags #software
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
printf 'official answer\n'
BASH
    chmod +x "$wrapper"
    printf '%s\n' "$wrapper"
}

write_fake_notify() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/notify-send" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/notify.args"
BASH
    chmod +x "${bin}/notify-send"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
foam-remind-agent-run-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
foam-remind-agent-run-writes-result-and-payload)
    notes=$(make_foam)
    wrapper=$(write_fake_wrapper)
    bin=$(write_fake_notify)

    PATH="${bin}:/usr/bin:/bin" \
        FOAM_REMIND_NOTES_ROOT="$notes" \
        FOAM_REMIND_AGENT_OUTPUT_ROOT="${notes}/misc/agent-runs" \
        FOAM_REMIND_AGENT_WRAPPER="$wrapper" \
        "$script_under_test" todo-audio-software-deal >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q -- '--agent codex --input-json -' "${DOTFILES_TEST_TMP}/wrapper.args"
    python - "${DOTFILES_TEST_TMP}/wrapper.payload" "$notes" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
notes = sys.argv[2]
assert payload["schema"] == "foam-ai-autotrigger.v1"
assert payload["todo"]["id"] == "todo-audio-software-deal"
assert payload["todo"]["title"] == "review the audio software deal"
assert payload["todo"]["body"] == "Check whether there is an official deal."
assert payload["todo"]["tags"] == ["#software"]
assert payload["execution"]["agent"] == "codex"
assert payload["execution"]["model"] == "gpt-test"
assert payload["execution"]["cwd"] == notes
assert payload["source"]["relative_file"] == "misc/finance/todos.finance.md"
PY
    result=$(find "${notes}/misc/agent-runs" -type f -name 'todo-audio-software-deal-*.md' -print -quit)
    [[ -n "$result" ]]
    rg -q "source: \\[\\[todos.finance#\\^todo-audio-software-deal\\]\\]" "$result"
    rg -q "status: completed" "$result"
    rg -q "official answer" "$result"
    [[ "$(cat "${DOTFILES_TEST_TMP}/notify.args")" == "Agent TODO completed todo-audio-software-deal" ]]
    ;;
foam-remind-agent-run-fails-on-duplicate-id)
    notes=$(make_foam)
    cat >>"${notes}/misc/finance/todos.finance.md" <<'MARKDOWN'

- [ ] **duplicate**
  @id todo-audio-software-deal
MARKDOWN
    wrapper=$(write_fake_wrapper)
    bin=$(write_fake_notify)

    if PATH="${bin}:/usr/bin:/bin" FOAM_REMIND_NOTES_ROOT="$notes" FOAM_REMIND_AGENT_WRAPPER="$wrapper" "$script_under_test" todo-audio-software-deal >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
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

