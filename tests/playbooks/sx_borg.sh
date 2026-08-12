#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks borg sx shell fast
# dotfiles-test-case: sx-borg-template-renders-and-syntax-checks
# dotfiles-test-case: sx-borg-lists-available-devices-and-repos
# dotfiles-test-case: sx-borg-command-first-resolves-repo-and-keys
# dotfiles-test-case: sx-borg-repo-first-order-works
# dotfiles-test-case: sx-borg-info-joins-archive-token
# dotfiles-test-case: sx-borg-mount-keeps-mountpoint
# dotfiles-test-case: sx-borg-root-backup-uses-root-passwords-folder
# dotfiles-test-case: sx-borg-full-path-form
# dotfiles-test-case: sx-borg-borg-repo-env-fallback
# dotfiles-test-case: sx-borg-key-subcommand
# dotfiles-test-case: sx-borg-delete-forwards-multiple-archives
# dotfiles-test-case: sx-borg-errors-on-bad-input

# Purpose: Hermetic tests for the Ansible-generated `sx borg` shortcut
#   (for-my-eyes-only role 80 template sx-borg). Renders the template with
#   fixture device bases, runs the script against a fake borgb in PATH, and
#   asserts the resolved borg invocation (repo path + KWallet keyring) and the
#   available-devices listing. The fixture bases embed a literal
#   `/data/backups/` component because the script derives the KWallet passkey
#   from the repo path substring after that prefix.

skip_missing_jinja2() {
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import jinja2
PY
        printf 'SKIP: python jinja2 module is required to render the sx-borg template\n' >&2
        exit 77
    fi
}

make_fixture() {
    skip_missing_jinja2

    fixture="${DOTFILES_TEST_TMP}/fixture"
    home="${fixture}/home"
    bin="${fixture}/bin"
    borgb_log="${fixture}/borgb.log"
    output="${fixture}/output.log"
    bases="${fixture}/bases"

    rm -rf "$fixture"
    mkdir -p "$home/bin" "$bin" "$bases"

    cat >"${bin}/borgb" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$borgb_log"
SH
    chmod +x "${bin}/borgb"

    cat >"${fixture}/render-sx-borg.py" <<'PY'
from pathlib import Path
import os
import stat

import jinja2

test_root = Path(os.environ["DOTFILES_TEST_ROOT"])
fixture = Path(os.environ["SX_BORG_TEST_FIXTURE"])
template_path = (
    test_root
    / "for-my-eyes-only/playbooks/roles/80-for-my-eyes-only/templates/sx-borg"
)
rendered_path = fixture / "home/bin/sx-borg"

env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
template = env.from_string(template_path.read_text())
rendered = template.render(
    ansible_managed="Ansible managed: sx-borg test fixture",
    borg_devices=[
        {"alias": "dev2", "base": str(fixture / "bases/dev2/data/backups")},
        {"alias": "dev3", "base": str(fixture / "bases/dev3/data/backups")},
        {"alias": "dev4", "base": str(fixture / "bases/dev4/data/backups")},
    ],
)
rendered_path.parent.mkdir(parents=True, exist_ok=True)
rendered_path.write_text(rendered)
rendered_path.chmod(rendered_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY

    SX_BORG_TEST_FIXTURE="$fixture" python3 "${fixture}/render-sx-borg.py"
}

run_sx_borg() {
    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$home/bin/sx-borg" "$@"
}

assert_borgb_called() {
    local expected=$1

    grep -Fxq -- "$expected" "$borgb_log" || {
        printf 'borgb was not called as expected\n' >&2
        printf '  wanted: %s\n' "$expected" >&2
        printf '  got:\n' >&2
        cat "$borgb_log" >&2
        exit 1
    }
}

case "${DOTFILES_TEST_CASE:-}" in
sx-borg-template-renders-and-syntax-checks)
    make_fixture

    bash -n "$home/bin/sx-borg"
    grep -Fq "[\"dev4\"]=\"${bases}/dev4/data/backups\"" "$home/bin/sx-borg"
    ;;
sx-borg-lists-available-devices-and-repos)
    make_fixture
    mkdir -p "${bases}/dev4/data/backups/config-files" "${bases}/dev4/data/backups/PKM"

    run_sx_borg >"$output"

    grep -Fq -- "- dev4 (${bases}/dev4/data/backups) -> config-files, PKM" "$output"
    grep -Fq -- "- dev2 (${bases}/dev2/data/backups) -> disconnected" "$output"
    grep -Fq -- "- dev3 (${bases}/dev3/data/backups) -> disconnected" "$output"
    ;;
sx-borg-command-first-resolves-repo-and-keys)
    make_fixture

    run_sx_borg dev4 list config-files
    assert_borgb_called "-f borg-passwords -p config-files -w kdewallet -- borg list ${bases}/dev4/data/backups/config-files"
    ;;
sx-borg-repo-first-order-works)
    make_fixture

    run_sx_borg dev4 ai-conversations list
    assert_borgb_called "-f borg-passwords -p ai-conversations -w kdewallet -- borg list ${bases}/dev4/data/backups/ai-conversations"
    ;;
sx-borg-info-joins-archive-token)
    make_fixture

    run_sx_borg dev4 ai-conversations info archlinux-2026-08-10_18_02_49
    assert_borgb_called "-f borg-passwords -p ai-conversations -w kdewallet -- borg info ${bases}/dev4/data/backups/ai-conversations::archlinux-2026-08-10_18_02_49"
    ;;
sx-borg-mount-keeps-mountpoint)
    make_fixture

    run_sx_borg dev4 user-data mount /tmp/borg-mnt
    assert_borgb_called "-f borg-passwords -p user-data -w kdewallet -- borg mount ${bases}/dev4/data/backups/user-data /tmp/borg-mnt"
    ;;
sx-borg-root-backup-uses-root-passwords-folder)
    make_fixture

    run_sx_borg dev4 root-backup list
    assert_borgb_called "-f borg-root-passwords -p root-backup -w kdewallet -- borg list ${bases}/dev4/data/backups/root-backup"
    ;;
sx-borg-full-path-form)
    make_fixture

    run_sx_borg list "${bases}/dev4/data/backups/config-files"
    assert_borgb_called "-f borg-passwords -p config-files -w kdewallet -- borg list ${bases}/dev4/data/backups/config-files"
    ;;
sx-borg-borg-repo-env-fallback)
    make_fixture

    BORG_REPO="${bases}/dev4/data/backups/bw-backup" run_sx_borg list
    assert_borgb_called "-f borg-passwords -p bw-backup -w kdewallet -- borg list"
    ;;
sx-borg-key-subcommand)
    make_fixture

    run_sx_borg dev4 key export ai-conversations
    run_sx_borg dev4 ai-conversations key export
    assert_borgb_called "-f borg-passwords -p ai-conversations -w kdewallet -- borg key export ${bases}/dev4/data/backups/ai-conversations"
    [ "$(grep -c 'borg key export' "$borgb_log")" -eq 2 ]
    ;;
sx-borg-delete-forwards-multiple-archives)
    make_fixture

    run_sx_borg dev4 config-files delete arch-2026-08-10_18_02_49 arch-2026-08-11_09_00_00
    assert_borgb_called "-f borg-passwords -p config-files -w kdewallet -- borg delete ${bases}/dev4/data/backups/config-files::arch-2026-08-10_18_02_49 arch-2026-08-11_09_00_00"
    ;;
sx-borg-errors-on-bad-input)
    make_fixture

    if run_sx_borg nosuch list config-files >"$output" 2>&1; then
        printf 'unknown device should not resolve to a borg invocation\n' >&2
        exit 1
    fi
    grep -Fq 'could not find a borg repo in the arguments' "$output"

    if run_sx_borg dev4 >"$output" 2>&1; then
        printf 'bare device alias should be an error\n' >&2
        exit 1
    fi
    grep -Fq 'expected <command> <repo> or <repo> <command>' "$output"

    if run_sx_borg dev4 list >"$output" 2>&1; then
        printf 'missing repo name should be an error\n' >&2
        exit 1
    fi
    grep -Fq 'missing repo name, e.g. config-files' "$output"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
