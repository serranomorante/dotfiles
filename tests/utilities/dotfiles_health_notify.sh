#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities system-health performance notifications go shell
# dotfiles-test-case: dotfiles-health-notify-go-test
# dotfiles-test-case: dotfiles-health-notify-does-not-refresh-report-before-xorg-notification
# dotfiles-test-case: dotfiles-health-notify-ignores-non-xorg-spike-events
# dotfiles-test-case: dotfiles-health-notify-sends-ansible-warning-and-error
# dotfiles-test-case: dotfiles-health-notify-ignores-ansible-debug-and-ignored-error

# Purpose: Verify System Health notifications are sent from watched event files.

notify_source="${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/dotfiles-health-notify"

build_notify_binary() {
    local out="${DOTFILES_TEST_TMP}/bin/dotfiles-health-notify"
    mkdir -p "${DOTFILES_TEST_TMP}/bin" "${DOTFILES_TEST_TMP}/gocache" "${DOTFILES_TEST_TMP}/gotmp"
    (
        cd "$notify_source"
        GOWORK=off GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" go build -buildvcs=false -trimpath -ldflags="-s -w" -o "$out" .
    )
    printf '%s\n' "$out"
}

write_fake_tools() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/dotfiles-spikes" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/dotfiles-spikes.calls"
BASH
    chmod +x "${bin}/dotfiles-spikes"
    cat >"${bin}/notification-action" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "---" >>"${DOTFILES_TEST_TMP}/notification-action.args"
printf '%s\n' "$@" >>"${DOTFILES_TEST_TMP}/notification-action.args"
BASH
    chmod +x "${bin}/notification-action"
    printf '%s\n' "$bin"
}

append_spike_event() {
    local state=$1
    local event_id=$2
    local victim_kind=$3
    local comm=$4
    mkdir -p "${state}/events"
    cat >>"${state}/events/2026-06-04.jsonl" <<JSON
{"schema_version":1,"event_id":"${event_id}","started_at":"2026-06-04T19:42:00+02:00","ended_at":"2026-06-04T19:42:03+02:00","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"${comm}","unit":"sddm.service"},"trigger_cpu_pct":71.0,"victim":{"pid":1320,"comm":"${comm}","unit":"sddm.service"},"victim_kind":"${victim_kind}","top_processes":[{"pid":1320,"comm":"${comm}","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":71.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":71.0}],"suspects":[{"pid":171621,"comm":"xrandr","cmdline":"xrandr --query","unit":"display-health-check.service","cpu_pct":45.0,"first_seen":0.1,"last_seen":2.9,"reason":"command xrandr consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to display-health-check.service"}
JSON
}

append_ansible_event() {
    local state=$1
    local severity=$2
    local event_type=$3
    local ignored=$4
    local message=$5
    mkdir -p "${state}/events"
    cat >>"${state}/events/2026-07-17.jsonl" <<JSON
{"schema":"dotfiles.ansible-event.v1","timestamp":"2026-07-17T16:31:48+02:00","severity":"${severity}","event_type":"${event_type}","ignored":${ignored},"host":"localhost","task":"Controlled ansible task","playbook":"/tmp/test.yml","cwd":"/home/aaaa/dotfiles/playbooks","run_id":"run-${severity}-${event_type}-${ignored}","controller":"archlinux","message":"${message}"}
JSON
}

run_once() {
    local script_under_test=$1
    local bin=$2
    local home=$3
    local spike_state=$4
    local ansible_state=$5
    HOME="$home" PATH="${bin}:/usr/bin:/bin" DOTFILES_SPIKES_STATE_DIR="$spike_state" DOTFILES_ANSIBLE_EVENTS_DIR="$ansible_state" DOTFILES_HEALTH_NOTIFY_STATE_DIR="${DOTFILES_TEST_TMP}/notify-state" DOTFILES_HEALTH_NOTIFY_FOAM_CWD="${DOTFILES_TEST_TMP}/foam" DOTFILES_HEALTH_NOTIFY_RECENT_DAYS=0 "$script_under_test" once
}

case "${DOTFILES_TEST_CASE:-}" in
dotfiles-health-notify-go-test)
    mkdir -p "${DOTFILES_TEST_TMP}/gocache" "${DOTFILES_TEST_TMP}/gotmp"
    (
        cd "$notify_source"
        GOWORK=off GOCACHE="${DOTFILES_TEST_TMP}/gocache" GOTMPDIR="${DOTFILES_TEST_TMP}/gotmp" go test ./...
    )
    ;;
dotfiles-health-notify-does-not-refresh-report-before-xorg-notification)
    script_under_test=$(build_notify_binary)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    spike_state="${DOTFILES_TEST_TMP}/spike-state"
    ansible_state="${DOTFILES_TEST_TMP}/ansible-state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    mkdir -p "$home"
    append_spike_event "$spike_state" old-xorg xorg Xorg

    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"
    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]
    [[ ! -e "${DOTFILES_TEST_TMP}/dotfiles-spikes.calls" ]]

    append_spike_event "$spike_state" new-xorg xorg Xorg
    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"

    [[ ! -e "${DOTFILES_TEST_TMP}/dotfiles-spikes.calls" ]]
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
    [[ ! -e "${foam}/system-spikes.md" ]]
    rg -q '^spike:xorg:new-xorg$' "${DOTFILES_TEST_TMP}/notify-state/notify/notified-events"
    ;;
dotfiles-health-notify-ignores-non-xorg-spike-events)
    script_under_test=$(build_notify_binary)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    spike_state="${DOTFILES_TEST_TMP}/spike-state"
    ansible_state="${DOTFILES_TEST_TMP}/ansible-state"
    mkdir -p "$home"
    append_spike_event "$spike_state" brave-event generic brave

    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"

    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]
    [[ ! -s "${DOTFILES_TEST_TMP}/notify-state/notify/notified-events" ]]
    ;;
dotfiles-health-notify-sends-ansible-warning-and-error)
    script_under_test=$(build_notify_binary)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    spike_state="${DOTFILES_TEST_TMP}/spike-state"
    ansible_state="${DOTFILES_TEST_TMP}/ansible-state"
    mkdir -p "$home"

    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"
    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]

    append_ansible_event "$ansible_state" warning task_warning false "controlled warning"
    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"
    rg -q '^Ansible warning$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q '^normal$' "${DOTFILES_TEST_TMP}/notification-action.args"

    rm -f "${DOTFILES_TEST_TMP}/notification-action.args"

    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]

    append_ansible_event "$ansible_state" error task_failed false "controlled failure"
    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"

    rg -q '^Ansible error$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q '^Open health$' "${DOTFILES_TEST_TMP}/notification-action.args"
    rg -q '^critical$' "${DOTFILES_TEST_TMP}/notification-action.args"
    python3 - "${DOTFILES_TEST_TMP}/notification-action.args" "${DOTFILES_TEST_TMP}/foam" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[-1])
assert payload["schema"] == "dotfiles.notification-action.v1"
assert payload["action"] == "open-foam-block-section"
assert payload["cwd"] == sys.argv[2]
assert payload["foam-section-id"] == "system-health-ansible"
PY
    ;;
dotfiles-health-notify-ignores-ansible-debug-and-ignored-error)
    script_under_test=$(build_notify_binary)
    bin=$(write_fake_tools)
    home="${DOTFILES_TEST_TMP}/home"
    spike_state="${DOTFILES_TEST_TMP}/spike-state"
    ansible_state="${DOTFILES_TEST_TMP}/ansible-state"
    mkdir -p "$home"
    append_ansible_event "$ansible_state" debug repository_event false "debug event"
    append_ansible_event "$ansible_state" error task_failed true "ignored failure"

    run_once "$script_under_test" "$bin" "$home" "$spike_state" "$ansible_state"

    [[ ! -e "${DOTFILES_TEST_TMP}/notification-action.args" ]]
    [[ ! -s "${DOTFILES_TEST_TMP}/notify-state/notify/notified-events" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
