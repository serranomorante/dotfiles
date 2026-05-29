#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks wine shell xvfb
# dotfiles-test-firejail: disabled
# dotfiles-test-case: wwine-template-renders-and-has-shell-syntax
# dotfiles-test-case: wwine-opens-light-wine-window-with-and-without-desktop

# Purpose: Verify wwine's virtual-desktop toggle with a temporary Wine prefix.

skip_missing_commands() {
    local missing=0
    local command_name

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'SKIP: required command not found: %s\n' "$command_name" >&2
            missing=1
        fi
    done

    [[ "$missing" -eq 0 ]] || exit 77
}

skip_missing_jinja2() {
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import jinja2
PY
        printf 'SKIP: python jinja2 module is required to render the wwine template\n' >&2
        exit 77
    fi
}

render_wwine() {
    local renderer="${DOTFILES_TEST_TMP}/render-wwine.py"
    local rendered="${DOTFILES_TEST_TMP}/bin/wwine"

    mkdir -p "${DOTFILES_TEST_TMP}/bin"
    cat >"$renderer" <<'PY'
from pathlib import Path
import os
import stat

import jinja2

test_root = Path(os.environ["DOTFILES_TEST_ROOT"])
test_tmp = Path(os.environ["DOTFILES_TEST_TMP"])
template_path = test_root / "playbooks/roles/10-system-tools/templates/wwine"
rendered_path = test_tmp / "bin/wwine"

env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
template = env.from_string(template_path.read_text())
rendered = template.render(
    ansible_facts={
        "env": {
            "HOME": os.environ["HOME"],
            "PATH": "/usr/bin:/bin",
        },
    },
    wine_env_vars={
        "WINEVERPATH": "/usr",
        "WINELOADER": "/usr/bin/wine",
        "WINESERVER": "/usr/bin/wineserver",
        "WINEDLLPATH": "",
        "LD_LIBRARY_PATH": "",
        "PATH": "/usr/bin:/bin",
        "WINEFSYNC": "0",
    },
    wwine_prefix_aliases={
        "dotfiles-test": {
            "path": str(test_tmp / "wine-prefix"),
            "architecture": "win64",
        },
    },
)

rendered_path.write_text(rendered)
rendered_path.chmod(rendered_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY

    python3 "$renderer"
    printf '%s\n' "$rendered"
}

run_wwine() {
    local wwine=$1
    shift

    WINEDEBUG=-all WINEDLLOVERRIDES=mscoree,mshtml= timeout 60s "$wwine" --prefix dotfiles-test "$@"
}

wait_for_notepad_window() {
    local tree_log=$1
    local i

    for ((i = 0; i < 40; i++)); do
        xwininfo -root -tree >"$tree_log" 2>/dev/null || true
        if grep -Eq 'Untitled - Notepad|Notepad|notepad\.exe' "$tree_log"; then
            return 0
        fi
        sleep 0.25
    done

    return 1
}

open_notepad_and_assert_window() {
    local wwine=$1
    local tree_log=$2
    shift 2
    local attempt
    local wine_pid

    for ((attempt = 1; attempt <= 3; attempt++)); do
        : >"${DOTFILES_TEST_TMP}/notepad.stdout"
        : >"${DOTFILES_TEST_TMP}/notepad.stderr"
        WINEDEBUG=-all WINEDLLOVERRIDES=mscoree,mshtml= "$wwine" --prefix dotfiles-test "$@" wine notepad >"${DOTFILES_TEST_TMP}/notepad.stdout" 2>"${DOTFILES_TEST_TMP}/notepad.stderr" &
        wine_pid=$!

        wait_for_notepad_window "$tree_log" || true
        kill "$wine_pid" 2>/dev/null || true
        wait "$wine_pid" 2>/dev/null || true
        run_wwine "$wwine" wineserver -k >/dev/null 2>&1 || true

        if grep -Eq 'Untitled - Notepad|Notepad|notepad\.exe' "$tree_log"; then
            return 0
        fi

        sleep 1
    done

    printf 'Notepad did not open after retries. Last window tree:\n' >&2
    sed -n '1,120p' "$tree_log" >&2
    printf 'Last stderr:\n' >&2
    sed -n '1,120p' "${DOTFILES_TEST_TMP}/notepad.stderr" >&2
    return 1
}

assert_registry_has_desktop() {
    local wwine=$1
    local expected_name=$2
    local expected_size=$3

    run_wwine "$wwine" wine reg query 'HKEY_CURRENT_USER\Software\Wine\Explorer' /v Desktop >"${DOTFILES_TEST_TMP}/desktop.reg"
    grep -Eq "Desktop[[:space:]]+REG_SZ[[:space:]]+${expected_name}[[:space:]]*$" "${DOTFILES_TEST_TMP}/desktop.reg"

    run_wwine "$wwine" wine reg query 'HKEY_CURRENT_USER\Software\Wine\Explorer\Desktops' /v "$expected_name" >"${DOTFILES_TEST_TMP}/desktop-size.reg"
    grep -Eq "${expected_name}[[:space:]]+REG_SZ[[:space:]]+${expected_size}[[:space:]]*$" "${DOTFILES_TEST_TMP}/desktop-size.reg"
}

assert_registry_has_no_active_desktop() {
    local wwine=$1

    if run_wwine "$wwine" wine reg query 'HKEY_CURRENT_USER\Software\Wine\Explorer' /v Desktop >"${DOTFILES_TEST_TMP}/desktop-after-no-desktop.reg" 2>&1; then
        printf 'Expected wwine --no-desktop to remove the active Wine desktop value, but it remains:\n' >&2
        cat "${DOTFILES_TEST_TMP}/desktop-after-no-desktop.reg" >&2
        return 1
    fi

    grep -q 'Unable to find the specified registry value' "${DOTFILES_TEST_TMP}/desktop-after-no-desktop.reg"
}

run_desktop_toggle_test() {
    mkdir -p "${DOTFILES_TEST_TMP}/wine-prefix"
    # shellcheck disable=SC2016
    xvfb-run -a --server-args="-screen 0 1024x768x24" bash -c '
        set -euo pipefail

        source "$DOTFILES_TEST_TMP/test-functions.bash"
        run_wwine "$WWINE_UNDER_TEST" wine reg query "HKEY_CURRENT_USER\\Software\\Wine" >/dev/null 2>&1 || true
        run_wwine "$WWINE_UNDER_TEST" wineserver -w >/dev/null 2>&1 || true

        open_notepad_and_assert_window "$WWINE_UNDER_TEST" "$DOTFILES_TEST_TMP/with-desktop.tree" --desktop=640x480 --desktop-name DotfilesTest
        assert_registry_has_desktop "$WWINE_UNDER_TEST" DotfilesTest 640x480

        open_notepad_and_assert_window "$WWINE_UNDER_TEST" "$DOTFILES_TEST_TMP/without-desktop.tree" --no-desktop
        assert_registry_has_no_active_desktop "$WWINE_UNDER_TEST"
    '
}

write_function_exports() {
    declare -f run_wwine wait_for_notepad_window open_notepad_and_assert_window assert_registry_has_desktop assert_registry_has_no_active_desktop >"${DOTFILES_TEST_TMP}/test-functions.bash"
}

case "${DOTFILES_TEST_CASE:-}" in
wwine-template-renders-and-has-shell-syntax)
    skip_missing_commands bash python3
    skip_missing_jinja2
    rendered=$(render_wwine)
    bash -n "$rendered"
    ;;
wwine-opens-light-wine-window-with-and-without-desktop)
    skip_missing_commands bash grep python3 sed sleep timeout wine wineserver xvfb-run xwininfo
    skip_missing_jinja2
    rendered=$(render_wwine)
    bash -n "$rendered"
    write_function_exports
    export WWINE_UNDER_TEST="$rendered"
    run_desktop_toggle_test
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
