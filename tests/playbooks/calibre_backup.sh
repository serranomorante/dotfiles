#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks backup calibre shell fast
# dotfiles-test-case: calibre-backup-export-refreshes-staging-and-calls-native-export
# dotfiles-test-case: calibre-backup-import-extracts-then-restores
# dotfiles-test-case: calibre-backup-import-moves-existing-library-aside
# dotfiles-test-case: calibre-backup-import-defaults-to-real-library-parent
# dotfiles-test-case: calibre-backup-import-fails-without-sx
# dotfiles-test-case: calibre-backup-export-dir-is-backed-up-by-user-data-repos

# Purpose: Hermetic tests for the private `calibre-backup` wrapper. The export
#   path is exercised with a fake `calibre-debug` in PATH so the native binary
#   is never invoked; the import path is exercised with a fake `sx` that logs
#   the borg subcommands and fabricates the extracted `part-*.calibre-data`
#   tree. Import now defaults to the real library parent (/srv/media/books)
#   and moves any existing content aside into CALIBRE_RESTORE_DIR so a restore
#   never leaves a shadow library registered in calibre. A final case checks
#   the backups.vars.yml invariant that the staged export dir is part of the
#   user-data backup and that each user-data repo runs the export as its
#   pre-backup hook.

wrapper="$DOTFILES_TEST_ROOT/for-my-eyes-only/bin/calibre-backup"

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/fixture"
    fakebin="${fixture}/fakebin"
    debuglog="${fixture}/calibre-debug.log"
    sxlog="${fixture}/sx.log"

    rm -rf "$fixture"
    mkdir -p "$fakebin"

    cat >"${fakebin}/calibre-debug" <<'SH'
#!/usr/bin/env sh
log="${CALIBRE_TEST_DEBUG_LOG}"
if [ "$1" = "--import-calibre-data" ]; then
    printf 'IMPORT\n' >>"$log"
    IFS= read -r d1
    IFS= read -r d2
    printf 'EXPORT_DIR=%s\n' "$d1" >>"$log"
    printf 'LIBRARY_DIR=%s\n' "$d2" >>"$log"
else
    printf 'EXPORT_ARGS=%s\n' "$*" >>"$log"
fi
SH

    cat >"${fakebin}/sx" <<'SH'
#!/usr/bin/env sh
log="${CALIBRE_TEST_SX_LOG}"
printf 'SX %s\n' "$*" >>"$log"
if [ "$3" = "list" ]; then
    printf 'archlinux-2026-08-17_10_00_00\n'
elif [ "$3" = "extract" ]; then
    subpath=$6
    mkdir -p "$subpath"
    : >"$subpath/part-0001.calibre-data"
fi
SH

    chmod +x "${fakebin}/calibre-debug" "${fakebin}/sx"
}

run_calibre_backup() {
    PATH="${fixture}/fakebin:/usr/bin:/bin" \
        CALIBRE_TEST_DEBUG_LOG="$debuglog" \
        CALIBRE_TEST_SX_LOG="$sxlog" \
        CALIBRE_EXPORT_DIR="$exportdir" \
        "$wrapper" "$@"
}

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse backups.vars.yml\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
calibre-backup-export-refreshes-staging-and-calls-native-export)
    make_fixture
    exportdir="${fixture}/export"

    mkdir -p "$exportdir"
    : >"$exportdir/stale"

    run_calibre_backup

    [ -d "$exportdir" ]
    refute [ -e "$exportdir/stale" ]
    grep -Fq "EXPORT_ARGS=--export-all-calibre-data ${exportdir} all" "$debuglog"
    ;;
calibre-backup-import-extracts-then-restores)
    make_fixture
    exportdir="${fixture}/export"

    run_calibre_backup --import --library-dir "${fixture}/restore"

    grep -Fq 'SX borg dev4 list user-data --format {archive} --last 1' "$sxlog"
    grep -Fq 'SX borg dev4 extract user-data archlinux-2026-08-17_10_00_00 ' "$sxlog"
    grep -Fq 'IMPORT' "$debuglog"
    grep -Fq "LIBRARY_DIR=${fixture}/restore" "$debuglog"

    export_line=$(grep '^EXPORT_DIR=' "$debuglog")
    extracted_dir=${export_line#EXPORT_DIR=}
    [ -n "$extracted_dir" ]
    [ "$extracted_dir" != "$exportdir" ]
    printf '%s' "$extracted_dir" | grep -Fq "${exportdir#/}"
    ;;
calibre-backup-import-moves-existing-library-aside)
    make_fixture
    exportdir="${fixture}/export"
    mkdir -p "${fixture}/libs/calibre-library"
    : >"${fixture}/libs/calibre-library/metadata.db"
    : >"${fixture}/libs/calibre-library/Book.pdf"

    CALIBRE_LIBRARY_DIR="${fixture}/libs" \
        CALIBRE_RESTORE_DIR="${fixture}/old" \
        run_calibre_backup --import >"${fixture}/out" 2>&1

    refute [ -e "${fixture}/libs/calibre-library" ]
    bak=$(find "${fixture}/old" -maxdepth 1 -type d -name 'calibre-library.bak-*')
    [ -n "$bak" ]
    [ -f "$bak/metadata.db" ]
    grep -Fq "LIBRARY_DIR=${fixture}/libs" "$debuglog"
    grep -Fq 'moved existing' "${fixture}/out"
    ;;
calibre-backup-import-defaults-to-real-library-parent)
    src="$(cat "$wrapper")"
    printf '%s' "$src" | grep -Fq 'CALIBRE_LIBRARY_DIR:-/srv/media/books'
    printf '%s' "$src" | grep -Fq 'CALIBRE_RESTORE_DIR:-$HOME/data/backups/calibre-restore'
    ;;
calibre-backup-import-fails-without-sx)
    make_fixture
    exportdir="${fixture}/export"

    mkdir -p "$fakebin"
    rm -f "$fakebin/sx"

    if run_calibre_backup --import >"${fixture}/out" 2>&1; then
        printf 'expected import to fail without sx\n' >&2
        exit 1
    fi
    grep -Fq 'sx not found' "${fixture}/out"
    ;;
calibre-backup-export-dir-is-backed-up-by-user-data-repos)
    skip_missing_yaml
    vars_file="$DOTFILES_TEST_ROOT/playbooks/roles/10-system-tools/defaults/main/backups.vars.yml"

    python3 - "$vars_file" "$wrapper" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    vars = yaml.safe_load(fh)

export_dir = vars["calibre_export_dir"]
assert export_dir == "~/data/backups/calibre-export", export_dir

# user_data_backup_env references calibre_export_dir via Jinja, so assert the
# reference (and not a divergent literal) is present.
entries = vars["user_data_backup_env"]
assert "{{ calibre_export_dir }}" in entries, entries

# Each user-data repo must run the export as its pre-backup hook.
user_data_repos = [r for r in vars["archlinux_borg_repos_env"] if r["sh_template"].endswith("user-data")]
assert len(user_data_repos) == 3, user_data_repos
for r in user_data_repos:
    assert r["pre_backup_hook"] == '"$HOME/bin/calibre-backup"', r["sh_template"]

# The wrapper default must match the staged dir so borg backs the same path.
wrapper_src = open(sys.argv[2]).read()
assert "$HOME/data/backups/calibre-export" in wrapper_src
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
