#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks storage automount sh fast
# dotfiles-test-case: automount-templates-render
# dotfiles-test-case: automount-mounts-when-connected
# dotfiles-test-case: automount-skips-when-already-mounted
# dotfiles-test-case: automount-skips-when-mounted-elsewhere
# dotfiles-test-case: automount-skips-unconfigured-uuid

# Purpose: Hermetic tests for the udev-triggered storage automount
#   (assets/scripts/storage/dotfiles-automount plus its udev rule template).
#   The script is read straight from the read-only repo; blkid/lsblk/
#   mountpoint/mount/chown are replaced with fake executables in PATH so no
#   host device or mount table is touched.

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

make_automount_fixture() {
    fixture="${DOTFILES_TEST_TMP}/automount-fixture"
    fake_bin="${fixture}/bin"
    mount_log="${fixture}/mount.log"
    chown_log="${fixture}/chown.log"
    FAKE_MOUNTS="${fixture}/fake-mounts"
    FAKE_LSBLK_MOUNTS="${fixture}/fake-lsblk-mounts"
    fixture_uuid="3dc52ee3-d7b3-4eb0-86aa-8237ca5c0ad7"
    mountpoint="${fixture}/mnt/dev4"

    rm -rf "${fixture}"
    mkdir -p "${fake_bin}"

    cat >"${fixture}/automounts.conf" <<EOF
# fixture automount config
${fixture_uuid} ${mountpoint} me
EOF

    cat >"${fake_bin}/blkid" <<SH
#!/usr/bin/env bash
if [ "\$1" = "-U" ]; then
    printf '%s\n' "/dev/mock-dev"
    exit 0
fi
exit 1
SH

    cat >"${fake_bin}/lsblk" <<SH
#!/usr/bin/env bash
for a in "\$@"; do
    [ "\$a" = "MOUNTPOINTS" ] || continue
    [ -r "${FAKE_LSBLK_MOUNTS}" ] && cat "${FAKE_LSBLK_MOUNTS}"
    exit 0
done
exit 0
SH

    cat >"${fake_bin}/mountpoint" <<SH
#!/usr/bin/env bash
target="\${@: -1}"
[ -r "${FAKE_MOUNTS}" ] || exit 1
grep -Fxq -- "\${target}" "${FAKE_MOUNTS}"
SH

    cat >"${fake_bin}/mount" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${mount_log}"
printf '%s\n' "\${@: -1}" >> "${FAKE_MOUNTS}"
exit 0
SH

    cat >"${fake_bin}/chown" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${chown_log}"
exit 0
SH

    chmod +x "${fake_bin}"/*

    export PATH="${fake_bin}:${PATH}"
    export DOTFILES_AUTOMOUNTS_CONF="${fixture}/automounts.conf"
}

run_automount() {
    "${DOTFILES_TEST_ROOT}/assets/scripts/storage/dotfiles-automount" "$1"
}

case "${DOTFILES_TEST_CASE:-}" in
automount-templates-render)
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import jinja2
PY
        printf 'SKIP: python jinja2 module is required to render the automount template\n' >&2
        exit 77
    fi
    python3 - <<'PY'
from pathlib import Path
import os

import jinja2

root = Path(os.environ["DOTFILES_TEST_ROOT"])
rule_tpl = (root / "playbooks/roles/10-system-tools/templates/70-dotfiles-automount.rules").read_text()
service = (root / "assets/services/dotfiles-automount@.service").read_text()
helper = (root / "assets/scripts/storage/dotfiles-automount").read_text()

env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
rule = env.from_string(rule_tpl).render(
    ansible_managed="Ansible managed: automount test fixture",
    arch_filesystem_automounts=[
        {"uuid": "3dc52ee3-d7b3-4eb0-86aa-8237ca5c0ad7", "mountpoint": "/run/media/me/dev4", "owner": "me"}
    ],
)

assert 'SYSTEMD_WANTS}+="dotfiles-automount@3dc52ee3-d7b3-4eb0-86aa-8237ca5c0ad7.service"' in rule
assert 'ENV{ID_FS_UUID}=="3dc52ee3-d7b3-4eb0-86aa-8237ca5c0ad7"' in rule
assert "After=dotfiles-fs-label@%i.service" in service
assert "/usr/local/bin/dotfiles-automount" in service
assert "/usr/bin/env sh" in helper
print("automount templates render correctly")
PY
    ;;
automount-mounts-when-connected)
    make_automount_fixture
    run_automount "${fixture_uuid}"
    assert_line "${mount_log}" "-- /dev/mock-dev ${mountpoint}"
    assert_line "${chown_log}" "-- me ${mountpoint}"
    [ -d "${mountpoint}" ]
    assert_line "${FAKE_MOUNTS}" "${mountpoint}"
    ;;
automount-skips-when-already-mounted)
    make_automount_fixture
    printf '%s\n' "${mountpoint}" >"${FAKE_MOUNTS}"
    run_automount "${fixture_uuid}"
    refute [ -s "${mount_log}" ]
    refute [ -s "${chown_log}" ]
    ;;
automount-skips-when-mounted-elsewhere)
    make_automount_fixture
    printf '%s\n' "/somewhere/else" >"${FAKE_LSBLK_MOUNTS}"
    run_automount "${fixture_uuid}"
    refute [ -s "${mount_log}" ]
    ;;
automount-skips-unconfigured-uuid)
    make_automount_fixture
    run_automount "00000000-0000-0000-0000-000000000000"
    refute [ -s "${mount_log}" ]
    refute [ -s "${chown_log}" ]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
