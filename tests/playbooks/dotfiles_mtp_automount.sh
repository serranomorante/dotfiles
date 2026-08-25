#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks storage mtp sh fast
# dotfiles-test-case: mtp-templates-render
# dotfiles-test-case: mtp-mounts-when-connected
# dotfiles-test-case: mtp-skips-when-already-mounted
# dotfiles-test-case: mtp-skips-unconfigured-serial

# Purpose: Hermetic tests for the udev-triggered MTP automount
#   (assets/scripts/storage/dotfiles-mtp-automount plus its udev rule and
#   service templates). The script is read straight from the read-only repo;
#   jmtpfs/mountpoint are replaced with fake executables in PATH so no host
#   device or mount table is touched.

assert_line() {
    file="$1"
    want="$2"
    grep -Fxq -- "${want}" "${file}" || {
        printf 'expected %s to contain: %s\n' "${file}" "${want}" >&2
        printf 'got:\n' >&2
        cat "${file}" >&2 2>/dev/null || true
        exit 1
    }
}

make_mtp_fixture() {
    fixture="${DOTFILES_TEST_TMP}/mtp-fixture"
    fake_bin="${fixture}/bin"
    jmtpfs_log="${fixture}/jmtpfs.log"
    FAKE_MOUNTS="${fixture}/fake-mounts"
    fixture_serial="5DEEF0C9"
    mountpoint="${fixture}/boox"

    rm -rf "${fixture}"
    mkdir -p "${fake_bin}"

    cat >"${fixture}/mtp-automounts.conf" <<EOF
# fixture mtp automount config
${fixture_serial} ${mountpoint} me
EOF

    cat >"${fake_bin}/mountpoint" <<SH
#!/usr/bin/env bash
target="\${@: -1}"
[ -r "${FAKE_MOUNTS}" ] || exit 1
grep -Fxq -- "\${target}" "${FAKE_MOUNTS}"
SH

    cat >"${fake_bin}/jmtpfs" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${JMTPS_LOG}"
exit 0
SH

    chmod +x "${fake_bin}"/*

    export PATH="${fake_bin}:${PATH}"
    export DOTFILES_MTP_AUTOMOUNTS_CONF="${fixture}/mtp-automounts.conf"
    export JMTPS_LOG="${jmtpfs_log}"
}

run_mtp() {
    "${DOTFILES_TEST_ROOT}/assets/scripts/storage/dotfiles-mtp-automount" "$1"
}

case "${DOTFILES_TEST_CASE:-}" in
mtp-templates-render)
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import jinja2
PY
        printf 'SKIP: python jinja2 module is required to render the mtp automount templates\n' >&2
        exit 77
    fi
    python3 - <<'PY'
from pathlib import Path
import os

import jinja2

root = Path(os.environ["DOTFILES_TEST_ROOT"])
rule_tpl = (root / "playbooks/roles/10-system-tools/templates/70-dotfiles-mtp-automount.rules").read_text()
service = (root / "assets/services/dotfiles-mtp-automount@.service").read_text()
helper = (root / "assets/scripts/storage/dotfiles-mtp-automount").read_text()

env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
rule = env.from_string(rule_tpl).render(
    ansible_managed="Ansible managed: mtp test fixture",
    arch_mtp_automounts=[
        {"serial": "5DEEF0C9", "mountpoint": "/home/me/boox", "owner": "me"}
    ],
)

assert 'SYSTEMD_WANTS}+="dotfiles-mtp-automount@5DEEF0C9.service"' in rule
assert 'ATTR{serial}=="5DEEF0C9"' in rule
assert 'ENV{ID_MTP_DEVICE}=""' in rule
assert 'ENV{ID_MEDIA_PLAYER}=""' in rule
assert 'ACTION=="remove"' in rule
assert 'stop dotfiles-mtp-automount@5DEEF0C9.service' in rule
assert "/usr/local/bin/dotfiles-mtp-automount" in service
assert "/usr/bin/env sh" in helper
assert "jmtpfs" in helper
print("mtp automount templates render correctly")
PY
    ;;
mtp-mounts-when-connected)
    make_mtp_fixture
    run_mtp "${fixture_serial}"
    assert_line "${jmtpfs_log}" "-f -- ${mountpoint}"
    [ -d "${mountpoint}" ]
    ;;
mtp-skips-when-already-mounted)
    make_mtp_fixture
    printf '%s\n' "${mountpoint}" >"${FAKE_MOUNTS}"
    run_mtp "${fixture_serial}"
    refute [ -s "${jmtpfs_log}" ]
    ;;
mtp-skips-unconfigured-serial)
    make_mtp_fixture
    run_mtp "00000000"
    refute [ -s "${jmtpfs_log}" ]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
