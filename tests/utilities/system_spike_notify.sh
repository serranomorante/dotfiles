#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities system-health performance notifications shell
# dotfiles-test-case: system-spike-notify-syntax
# dotfiles-test-case: system-spike-notify-updates-report-before-xorg-notification
# dotfiles-test-case: system-spike-notify-ignores-non-xorg-events

# Purpose: Verify Xorg spike notifications are sent only after report refresh.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/system-spike-notify"

write_fake_tools() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/dotfiles-spikes" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/dotfiles-spikes.calls"
mkdir -p "${DOTFILES_SPIKES_DIR}"
printf '%s\n' '# System Spikes' '' 'This generated report is current.' '@id system-spikes-report' >"${DOTFILES_SPIKES_DIR}/system-spikes.md"
BASH
    chmod +x "${bin}/dotfiles-spikes"
    cat >"${bin}/notification-action" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/notification-action.args"
BASH
    chmod +x "${bin}/notification-action"
    printf '%s\n' "$bin"
}

append_event() {
    local state=$1
    local event_id=$2
    local victim_kind=$3
    local comm=$4
    mkdir -p "${state}/events"
    cat >>"${state}/events/2026-06-04.jsonl" <<JSON
{"schema_version":1,"event_id":"${event_id}","started_at":"2026-06-04T19:42:00+02:00","ended_at":"2026-06-04T19:42:03+02:00","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"${comm}","unit":"sddm.service"},"trigger_cpu_pct":71.0,"victim":{"pid":1320,"comm":"${comm}","unit":"sddm.service"},"victim_kind":"${victim_kind}","top_processes":[{"pid":1320,"comm":"${comm}","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":71.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":71.0}],"suspects":[{"pid":171621,"comm":"xrandr","cmdline":"xrandr --query","unit":"display-health-check.service","cpu_pct":45.0,"first_seen":0.1,"last_seen":2.9,"reason":"command xrandr consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to display-health-check.service"}
JSON
}

case "${DOTFILES_TEST_CASE:-}" in
system-spike-notify-syntax)
    bash -n "$script_under_test"
    ;;
system-spike-notify-updates-report-before-xorg-notification)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    mkdir -p "$home"
    append_event "$state" old-xorg xorg Xorg

    HOME="$home" PATH="${bin}:/usr/bin:/bin" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" DOTFILES_SPIKE_NOTIFY_FOAM_CWD="${DOTFILES_TEST_TMP}/foam" "$script_under_test" once
    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]
    rg -q '^update$' "${DOTFILES_TEST_TMP}/dotfiles-spikes.calls"

    append_event "$state" new-xorg xorg Xorg
    HOME="$home" PATH="${bin}:/usr/bin:/bin" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" DOTFILES_SPIKE_NOTIFY_FOAM_CWD="${DOTFILES_TEST_TMP}/foam" "$script_under_test" once

    [[ "$(wc -l <"${DOTFILES_TEST_TMP}/dotfiles-spikes.calls")" -eq 2 ]]
    rg -q '^send$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q '^Xorg CPU spike$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q '^Open report$' "${DOTFILES_TEST_TMP}/notification-action.args"
    python3 - "${DOTFILES_TEST_TMP}/notification-action.args" "${DOTFILES_TEST_TMP}/foam" <<'PY'
import json
import sys
from pathlib import Path

args = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
payload = json.loads(args[-1])
assert payload["schema"] == "dotfiles.notification-action.v1"
assert payload["action"] == "open-foam-block-section"
assert payload["cwd"] == sys.argv[2]
assert payload["foam-section-id"] == "system-spikes-report"
PY
    rg -q '@id system-spikes-report' "${foam}/system-spikes.md"
    rg -q '^new-xorg$' "${state}/notify/xorg-notified-events"
    ;;
system-spike-notify-ignores-non-xorg-events)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    mkdir -p "$home"
    append_event "$state" brave-event generic brave

    HOME="$home" PATH="${bin}:/usr/bin:/bin" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" DOTFILES_SPIKE_NOTIFY_FOAM_CWD="${DOTFILES_TEST_TMP}/foam" "$script_under_test" once

    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]
    [[ ! -s "${state}/notify/xorg-notified-events" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
