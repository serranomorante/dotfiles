#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities ai-autotrigger python
# dotfiles-test-case: agent-local-execution-syntax
# dotfiles-test-case: agent-local-execution-codex-builds-noninteractive-command
# dotfiles-test-case: agent-local-execution-claude-builds-noninteractive-command
# dotfiles-test-case: agent-local-execution-rejects-unsupported-schema

# Purpose: Verify the local agent wrapper contract without invoking real agents.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/agent-local-execution"

make_fake_path() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    ln -s /usr/bin/env "${bin}/env"
    ln -s /usr/bin/python "${bin}/python"
    ln -s /usr/bin/python3 "${bin}/python3"
    printf '%s\n' "$bin"
}

write_fake_agent() {
    local bin=$1
    local name=$2

    cat >"${bin}/${name}" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$0" >"${DOTFILES_TEST_TMP}/agent.argv0"
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/agent.args"
cat >"${DOTFILES_TEST_TMP}/agent.stdin"
printf 'agent result\n'
BASH
    chmod +x "${bin}/${name}"
}

write_payload() {
    local path="${DOTFILES_TEST_TMP}/payload.json"
    local cwd="${DOTFILES_TEST_TMP}/work"
    mkdir -p "$cwd"
    cat >"$path" <<JSON
{
  "schema": "foam-ai-autotrigger.v1",
  "source": {
    "file": "${DOTFILES_TEST_TMP}/notes/misc/todos/ai-autotrigger.todos.md",
    "relative_file": "misc/todos/ai-autotrigger.todos.md",
    "line": 12
  },
  "todo": {
    "title": "Run wrapped task",
    "id": "wrapped-task",
    "tags": ["#autotrigger"],
    "body": "Do the wrapped thing."
  },
  "execution": {
    "agent": "codex",
    "model": "gpt-5",
    "cwd": "${cwd}",
    "sandbox": "read-only",
    "timeout_seconds": 20
  }
}
JSON
    printf '%s\n' "$path"
}

run_wrapper_with_path() {
    local bin=$1
    shift

    PATH="${bin}:/usr/bin:/bin" "$script_under_test" "$@"
}

case "${DOTFILES_TEST_CASE:-}" in
agent-local-execution-syntax)
    PYTHONPYCACHEPREFIX="${DOTFILES_TEST_TMP}/pycache" python -m py_compile "$script_under_test"
    ;;
agent-local-execution-codex-builds-noninteractive-command)
    bin=$(make_fake_path)
    write_fake_agent "$bin" codex
    payload=$(write_payload)

    run_wrapper_with_path "$bin" --agent codex --input-json "$payload" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q "agent result" "${DOTFILES_TEST_TMP}/stdout"
    expected="-a never -s read-only -m gpt-5 exec --skip-git-repo-check --color never -C ${DOTFILES_TEST_TMP}/work -"
    actual=$(cat "${DOTFILES_TEST_TMP}/agent.args")
    [[ "$actual" == "$expected" ]]
    rg -q "title: Run wrapped task" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "id: wrapped-task" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "origin_link: \\[\\[ai-autotrigger.todos#\\^wrapped-task\\]\\]" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "include a backlink to the origin TODO" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "body:" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "Do the wrapped thing." "${DOTFILES_TEST_TMP}/agent.stdin"
    ;;
agent-local-execution-claude-builds-noninteractive-command)
    bin=$(make_fake_path)
    write_fake_agent "$bin" claude
    payload=$(write_payload)

    run_wrapper_with_path "$bin" --agent claude --input-json "$payload" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q "agent result" "${DOTFILES_TEST_TMP}/stdout"
    expected="-p --permission-mode dontAsk --output-format text --model gpt-5"
    actual=$(cat "${DOTFILES_TEST_TMP}/agent.args")
    [[ "$actual" == "$expected" ]]
    rg -q "agent: claude" "${DOTFILES_TEST_TMP}/agent.stdin"
    rg -q "model: gpt-5" "${DOTFILES_TEST_TMP}/agent.stdin"
    ;;
agent-local-execution-rejects-unsupported-schema)
    bin=$(make_fake_path)
    mkdir -p "${DOTFILES_TEST_TMP}/work"
    printf '{"schema":"bad.v1","todo":{},"execution":{"cwd":"%s"}}\n' "${DOTFILES_TEST_TMP}/work" >"${DOTFILES_TEST_TMP}/bad.json"

    if run_wrapper_with_path "$bin" --agent codex --input-json "${DOTFILES_TEST_TMP}/bad.json" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'wrapper unexpectedly succeeded\n' >&2
        exit 1
    fi

    rg -q "unsupported payload schema" "${DOTFILES_TEST_TMP}/stderr"
    [[ ! -e "${DOTFILES_TEST_TMP}/agent.args" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
