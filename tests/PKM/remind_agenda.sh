#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: pkm remind jq
# dotfiles-test-case: remind-agenda-syntax
# dotfiles-test-case: remind-agenda-suppresses-remind-stderr
# dotfiles-test-case: remind-agenda-preserves-remind-stderr-on-failure
# dotfiles-test-case: remind-agenda-excludes-agent-reminders-json
# dotfiles-test-case: remind-agenda-excludes-agent-reminders-markdown

# Purpose: Verify remind-agenda filtering against generated Remind metadata.

script_under_test="${DOTFILES_TEST_ROOT}/PKM/bin/remind-agenda"

write_fake_remind() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/remind" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${FAKE_REMIND_STDERR:-}" ]; then
    cat "${FAKE_REMIND_STDERR}" >&2
fi

if [ "${FAKE_REMIND_FAIL:-0}" -eq 1 ]; then
    exit 42
fi

cat "${FAKE_REMIND_OUTPUT:-${FAKE_REMIND_JSON}}"
BASH
    chmod +x "${bin}/remind"
    printf '%s\n' "$bin"
}

make_agenda() {
    local agenda_dir="${DOTFILES_TEST_TMP}/remind"
    mkdir -p "$agenda_dir"
    cat >"${agenda_dir}/reminders.rem" <<'REMIND'
# remind-agenda-meta run=agent tags=#planning
REM jun 1 2026 AT 10:00 MSG **Agent task** %b %1
# remind-agenda-meta tags=#autotrigger,#music-production
REM jun 1 2026 AT 11:00 MSG **Autotrigger task** %b %1
REM jun 1 2026 AT 12:00 MSG **Plain task** %b %1
REM jun 1 2026 AT 13:00 MSG **Legacy agent task** %b %1
REM jun 1 2026 AT 13:00 RUN '/home/example/bin/remind-run' 'agent' 'legacy-task'
REM jun 1 2026 AT 14:00 MSG **Health task** %b %1
REM jun 1 2026 AT 14:00 RUN '/home/example/bin/remind-run' 'dotfiles-health' 'update'
REMIND
    python - "$agenda_dir" >"${DOTFILES_TEST_TMP}/remind.json" <<'PY'
import json
import sys

path = sys.argv[1] + "/reminders.rem"
items = [
    {"date": "2026-06-01", "filename": path, "lineno": 2, "time": 600, "eventstart": "2026-06-01T10:00", "body": "**Agent task** today"},
    {"date": "2026-06-01", "filename": path, "lineno": 4, "time": 660, "eventstart": "2026-06-01T11:00", "body": "**Autotrigger task** today"},
    {"date": "2026-06-01", "filename": path, "lineno": 5, "time": 720, "eventstart": "2026-06-01T12:00", "body": "**Plain task** today"},
    {"date": "2026-06-01", "filename": path, "lineno": 6, "time": 780, "eventstart": "2026-06-01T13:00", "body": "**Legacy agent task** today"},
    {"date": "2026-06-01", "filename": path, "lineno": 8, "time": 840, "eventstart": "2026-06-01T14:00", "body": "**Health task** today"},
]
print(json.dumps(items))
PY
    printf '%s\n' "$agenda_dir"
}

run_agenda() {
    local agenda_dir=$1
    local bin=$2
    shift 2

    PATH="${bin}:/usr/bin:/bin" \
        REMIND_AGENDA_DIR="$agenda_dir" \
        REMIND_ONCE_FILE="${DOTFILES_TEST_TMP}/oncefile" \
        FAKE_REMIND_FAIL="${FAKE_REMIND_FAIL:-0}" \
        FAKE_REMIND_JSON="${DOTFILES_TEST_TMP}/remind.json" \
        FAKE_REMIND_OUTPUT="${FAKE_REMIND_OUTPUT:-}" \
        FAKE_REMIND_STDERR="${FAKE_REMIND_STDERR:-}" \
        "$script_under_test" "$@"
}

case "${DOTFILES_TEST_CASE:-}" in
remind-agenda-syntax)
    sh -n "$script_under_test"
    ;;
remind-agenda-suppresses-remind-stderr)
    agenda_dir=$(make_agenda)
    bin=$(write_fake_remind)
    printf '%s\n' 'some future remind warning' >"${DOTFILES_TEST_TMP}/fake-remind.err"
    printf '%s\n' '2026/06/01 **Plain task** today' >"${DOTFILES_TEST_TMP}/remind.txt"

    FAKE_REMIND_OUTPUT="${DOTFILES_TEST_TMP}/remind.txt" \
        FAKE_REMIND_STDERR="${DOTFILES_TEST_TMP}/fake-remind.err" \
        run_agenda "$agenda_dir" "$bin" --next-all --markdown >"${DOTFILES_TEST_TMP}/out.md" 2>"${DOTFILES_TEST_TMP}/err"

    rg -q '^- 2026/06/01 \*\*Plain task\*\* today$' "${DOTFILES_TEST_TMP}/out.md"
    [ ! -s "${DOTFILES_TEST_TMP}/err" ]
    ;;
remind-agenda-preserves-remind-stderr-on-failure)
    agenda_dir=$(make_agenda)
    bin=$(write_fake_remind)
    printf '%s\n' 'fatal remind parse error' >"${DOTFILES_TEST_TMP}/fake-remind.err"

    if FAKE_REMIND_FAIL=1 FAKE_REMIND_STDERR="${DOTFILES_TEST_TMP}/fake-remind.err" \
        run_agenda "$agenda_dir" "$bin" --next-all --markdown >"${DOTFILES_TEST_TMP}/out.md" 2>"${DOTFILES_TEST_TMP}/err"; then
        printf 'expected remind-agenda to fail\n' >&2
        exit 1
    fi

    rg -q '^fatal remind parse error$' "${DOTFILES_TEST_TMP}/err"
    ;;
remind-agenda-excludes-agent-reminders-json)
    agenda_dir=$(make_agenda)
    bin=$(write_fake_remind)

    run_agenda "$agenda_dir" "$bin" --days 1 --json --exclude-agent-reminders >"${DOTFILES_TEST_TMP}/out.json"

    python - "${DOTFILES_TEST_TMP}/out.json" <<'PY'
import json
import sys

items = json.load(open(sys.argv[1], encoding="utf-8"))
assert [item["body"] for item in items] == ["**Plain task** today", "**Health task** today"]
PY
    ;;
remind-agenda-excludes-agent-reminders-markdown)
    agenda_dir=$(make_agenda)
    bin=$(write_fake_remind)

    run_agenda "$agenda_dir" "$bin" --days 1 --markdown --exclude-agent-reminders >"${DOTFILES_TEST_TMP}/out.md"

    rg -q '\*\*Plain task\*\*' "${DOTFILES_TEST_TMP}/out.md"
    rg -q '\*\*Health task\*\*' "${DOTFILES_TEST_TMP}/out.md"
    ! rg -q '\*\*Agent task\*\*' "${DOTFILES_TEST_TMP}/out.md"
    ! rg -q '\*\*Autotrigger task\*\*' "${DOTFILES_TEST_TMP}/out.md"
    ! rg -q '\*\*Legacy agent task\*\*' "${DOTFILES_TEST_TMP}/out.md"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
