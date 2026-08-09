#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks wine shell xvfb
# dotfiles-test-firejail: disabled
# dotfiles-test-case: wwine-template-renders-and-has-shell-syntax
# dotfiles-test-case: wine-desktop-launchers-are-terminal-free-and-logged

# Purpose: Verify wwine's template rendering and the Wine desktop launcher contracts.

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
    ansible_managed="Ansible managed: test fixture",
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

assert_desktop_terminal_free() {
    local desktop_file=$1

    grep -Fxq "Terminal=false" "$desktop_file"
    refute grep -Fq "kitty" "$desktop_file"
    refute grep -Fq "Name=(debug)" "$desktop_file"
}

assert_launcher_uses_log_id() {
    local launcher_file=$1
    local log_id=$2

    grep -Fq -- "--log-id $log_id" "$launcher_file"
    refute grep -Fq "exec kitty" "$launcher_file"
    refute grep -Fq "kitty --hold" "$launcher_file"
}

assert_launcher_is_logged_and_terminal_free() {
    local launcher_file=$1

    grep -Eq -- "--log-id[[:space:]]+[^[:space:]]+" "$launcher_file"
    refute grep -Fq "exec kitty" "$launcher_file"
    refute grep -Fq "kitty --hold" "$launcher_file"
}

assert_private_wine_templates_are_terminal_free_and_logged() {
    local templates_dir=$1
    local desktop_file
    local launcher_file
    local exec_target

    [ -d "$templates_dir" ] || return 0

    while IFS= read -r -d '' desktop_file; do
        refute grep -Fxq "Terminal=true" "$desktop_file"
        refute grep -Fq "kitty" "$desktop_file"
        refute grep -Fq "Name=(debug)" "$desktop_file"

        exec_target=$(sed -n 's#^Exec=.*/\(launch-[^[:space:]]*\).*#\1#p' "$desktop_file")
        if [ -n "$exec_target" ]; then
            [ -f "${templates_dir}/${exec_target}" ]
        fi
    done < <(find "$templates_dir" -maxdepth 1 -type f -name "*.desktop" -print0)

    while IFS= read -r -d '' launcher_file; do
        assert_launcher_is_logged_and_terminal_free "$launcher_file"
    done < <(find "$templates_dir" -maxdepth 1 -type f -name "launch-*-wine" -print0)
}

case "${DOTFILES_TEST_CASE:-}" in
wwine-template-renders-and-has-shell-syntax)
    skip_missing_commands bash python3
    skip_missing_jinja2
    rendered=$(render_wwine)
    bash -n "$rendered"
    ;;
wine-desktop-launchers-are-terminal-free-and-logged)
    assert_desktop_terminal_free "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/reaper.desktop"
    assert_launcher_uses_log_id "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/launch-reaper-wine" "reaper"

    assert_desktop_terminal_free "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/audiogridder.desktop"
    assert_launcher_uses_log_id "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/launch-audiogridder-wine" "audiogridder"

    assert_desktop_terminal_free "${DOTFILES_TEST_ROOT}/utilities/dot-local/share/applications/resolve.desktop"

    assert_private_wine_templates_are_terminal_free_and_logged "${DOTFILES_TEST_ROOT}/for-my-eyes-only/playbooks/roles/60-for-my-eyes-only/templates"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
