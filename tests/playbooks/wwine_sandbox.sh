#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks wine firejail wwine shell fast
# dotfiles-test-firejail: disabled
# dotfiles-test-case: wwine-prepare-env-exports-sandbox-loader
# dotfiles-test-case: wwine-use-sandbox-starts-real-firejail-and-checks-profile
# dotfiles-test-case: wwine-wine-loader-mode-starts-real-firejail-and-preserves-args
# dotfiles-test-case: wwine-log-id-rotates-and-captures-output-before-sandbox
# dotfiles-test-case: wwine-reuses-existing-named-firejail-sandbox
# dotfiles-test-case: wwine-serializes-parallel-named-sandbox-startup
# dotfiles-test-case: wwine-fails-closed-when-inherited-sandbox-does-not-match-profile
# dotfiles-test-case: wwine-no-desktop-closes-running-wine-desktop-before-app
# dotfiles-test-case: wwine-no-desktop-taskkill-is-prefix-scoped

# Purpose: Fast real-Firejail tests for wwine sandbox startup, inherited sandbox verification, and loader mode.

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

require_tools() {
    skip_missing_commands awk bash firejail grep mkdir python3 sed sleep timeout
    skip_missing_jinja2
}

sanitize_case_name() {
    printf '%s\n' "${DOTFILES_TEST_CASE:-wwine}" | tr -c 'A-Za-z0-9_.-' '_'
}

make_fixture() {
    require_tools

    fixture="${DOTFILES_TEST_TMP}/fixture"
    home="${fixture}/home"
    runtime="${fixture}/runtime"
    readonly="${fixture}/readonly"
    hidden="${fixture}/hidden"
    wine_prefix="${fixture}/wine-prefix"
    other_wine_prefix="${fixture}/other-wine-prefix"
    fake_wine_log="${fixture}/fake-wine.log"
    fake_logrotate_log="${fixture}/fake-logrotate.log"
    checker_log="${fixture}/fj-profile-checker.log"
    output="${fixture}/output.log"
    sandbox_name="wwine-test-$(sanitize_case_name)-$$"
    sandbox_profile="${home}/.config/firejail/wine-reaper.local"
    sandbox_check_profile="${home}/.local/share/wwine/firejail-profiles/wine-reaper.local"
    writable_sandbox_profile="${home}/.config/firejail/wine-reaper-writable.local"

    mkdir -p \
        "${home}/bin" \
        "${home}/.config/firejail" \
        "${home}/.local/share/wwine/firejail-profiles" \
        "$runtime" \
        "$readonly" \
        "$hidden" \
        "$wine_prefix" \
        "$other_wine_prefix" \
        "${fixture}/fake-winever/bin"

    cat >"$sandbox_profile" <<PROFILE
quiet
whitelist ${fixture}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    cp "$sandbox_profile" "$sandbox_check_profile"

    cat >"$writable_sandbox_profile" <<PROFILE
quiet
whitelist ${fixture}
blacklist ${hidden}
PROFILE

    cat >"${home}/bin/fj-profile-checker" <<SH
#!/usr/bin/env sh
printf '%s\n' "\$*" >> "$checker_log"
exec "${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/files/fj-profile-checker" "\$@"
SH
    chmod +x "${home}/bin/fj-profile-checker"

    cat >"${fixture}/fake-wine" <<SH
#!/usr/bin/env sh
inside=0
if [ -d /run/firejail/profile ] && ! ls /run/firejail/profile >/dev/null 2>&1; then
  inside=1
fi
{
  printf 'INSIDE_FIREJAIL=%s\n' "\$inside"
  printf 'FIREJAIL_NAME=%s\n' "\${FIREJAIL_NAME:-}"
  printf 'WINEPREFIX=%s\n' "\${WINEPREFIX:-}"
  printf 'WINEARCH=%s\n' "\${WINEARCH:-}"
  printf 'ARGS='
  printf '<%s>' "\$@"
  printf '\n'
} >> "$fake_wine_log"
active_wine_desktop="${fixture}/active-wine-desktop-other"
if [ "\${WINEPREFIX:-}" = "$wine_prefix" ]; then
  active_wine_desktop="${fixture}/active-wine-desktop-reaper"
fi
for arg in "\$@"; do
  if [ "\$arg" = taskkill ]; then
    if printf '<%s>' "\$@" | grep -Fq '<explorer.exe>'; then
      rm -f "\$active_wine_desktop"
    fi
  fi
  if [ "\$arg" = start-desktop ]; then
    touch "\$active_wine_desktop"
  fi
  if [ "\$arg" = launch-after-desktop ]; then
    if [ -e "\$active_wine_desktop" ]; then
      printf 'OPENED_IN_DESKTOP=1\n' >> "$fake_wine_log"
    else
      printf 'OPENED_IN_DESKTOP=0\n' >> "$fake_wine_log"
    fi
  fi
  if [ "\$arg" = emit-output ]; then
    printf 'FAKE_WINE_STDOUT=1\n'
    printf 'FAKE_WINE_STDERR=1\n' >&2
  fi
  if [ "\$arg" = hold-sandbox ]; then
    touch "${fixture}/fake-wine-holding"
    while [ ! -e "${fixture}/stop-fake-wine" ]; do
      sleep 0.05
    done
  fi
done
SH
    chmod +x "${fixture}/fake-wine"

    cat >"${fixture}/fake-wineserver" <<SH
#!/usr/bin/env sh
printf 'WINESERVER_ARGS=' >> "$fake_wine_log"
printf '<%s>' "\$@" >> "$fake_wine_log"
printf '\n' >> "$fake_wine_log"
SH
    chmod +x "${fixture}/fake-wineserver"

    cat >"${fixture}/logrotate" <<SH
#!/usr/bin/env sh
printf 'LOGROTATE_ARGS=' >> "$fake_logrotate_log"
printf '<%s>' "\$@" >> "$fake_logrotate_log"
printf '\n' >> "$fake_logrotate_log"
SH
    chmod +x "${fixture}/logrotate"

    render_wwine
}

render_wwine() {
    local renderer="${fixture}/render-wwine.py"
    rendered="${home}/bin/wwine"
    wwine_loader="${home}/bin/wwine-wine-loader"

    cat >"$renderer" <<'PY'
from pathlib import Path
import os
import stat

import jinja2

test_root = Path(os.environ["DOTFILES_TEST_ROOT"])
fixture = Path(os.environ["WWINE_TEST_FIXTURE"])
home = fixture / "home"
template_path = test_root / "playbooks/roles/10-system-tools/templates/wwine"
rendered_path = home / "bin/wwine"

env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)
template = env.from_string(template_path.read_text())
rendered = template.render(
    ansible_facts={
        "env": {
            "HOME": str(home),
            "PATH": f"{fixture}:/usr/bin:/bin",
        },
    },
    wine_env_vars={
        "WINEVERPATH": str(fixture / "fake-winever"),
        "WINELOADER": str(fixture / "fake-wine"),
        "WINESERVER": str(fixture / "fake-wineserver"),
        "WINEDLLPATH": "",
        "LD_LIBRARY_PATH": "",
        "PATH": f"{fixture}:/usr/bin:/bin",
        "WINEFSYNC": "0",
    },
    wwine_prefix_aliases={
        "reaper": {
            "path": str(fixture / "wine-prefix"),
            "architecture": "win64",
            "sandbox_profile": str(home / ".config/firejail/wine-reaper.local"),
            "sandbox_check_profile": str(home / ".local/share/wwine/firejail-profiles/wine-reaper.local"),
            "sandbox_name": os.environ["WWINE_TEST_SANDBOX_NAME"],
        },
    },
)

rendered_path.write_text(rendered)
rendered_path.chmod(rendered_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY

    WWINE_TEST_FIXTURE="$fixture" WWINE_TEST_SANDBOX_NAME="$sandbox_name" python3 "$renderer"
    cp "$rendered" "$wwine_loader"
    chmod +x "$wwine_loader"
}

run_wwine() {
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime" \
    PATH="${fixture}:/usr/bin:/bin" \
    "$rendered" "$@"
}

run_loader() {
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime" \
    PATH="${fixture}:/usr/bin:/bin" \
    WWINE_PREFIX_ALIAS=reaper \
    WWINE_USE_SANDBOX=1 \
    WWINE_USE_DESKTOP=0 \
    WWINE_SANDBOX_PROFILE="$sandbox_profile" \
    WWINE_SANDBOX_CHECK_PROFILE="$sandbox_check_profile" \
    WWINE_SANDBOX_NAME="$sandbox_name" \
    "$wwine_loader" "$@"
}

shutdown_sandbox() {
    firejail "--shutdown=$sandbox_name" >/dev/null 2>&1 || true
}

wait_for_sandbox() {
    local i

    for ((i = 0; i < 80; i++)); do
        if firejail --list 2>/dev/null | awk -F: -v name="$sandbox_name" '$3 == name { found = 1 } END { exit found ? 0 : 1 }'; then
            return 0
        fi
        sleep 0.05
    done

    firejail --list >&2 || true
    return 1
}

wait_for_file() {
    local path="$1"
    local label="${2:-$1}"
    local i

    for ((i = 0; i < 80; i++)); do
        [ -e "$path" ] && return 0
        sleep 0.05
    done

    printf 'timed out waiting for %s\n' "$label" >&2
    return 1
}

install_firejail_race_wrapper() {
    local real_firejail

    real_firejail="$(command -v firejail)"
    firejail_wrapper_log="${fixture}/firejail-wrapper.log"

    cat >"${fixture}/firejail" <<SH
#!/usr/bin/env bash
set -euo pipefail

real_firejail=$real_firejail
fixture=$fixture
sandbox_name=$sandbox_name
log=$firejail_wrapper_log

is_named_start=0
for arg in "\$@"; do
  case "\$arg" in
    --join-or-start="\$sandbox_name")
      is_named_start=1
      ;;
  esac
done

if [[ "\$is_named_start" == 1 ]]; then
  {
    printf 'PROFILE_START %s ' "\$(date +%s%N)"
    printf '<%s>' "\$@"
    printf '\n'
  } >> "\$log"

  if [[ -e "\$fixture/simulate-firejail-race" ]]; then
    if mkdir "\$fixture/first-firejail-start.lock" 2>/dev/null; then
      touch "\$fixture/first-firejail-blocked"
      while [[ ! -e "\$fixture/allow-first-firejail" ]]; do
        sleep 0.05
      done
    elif ! "\$real_firejail" --list 2>/dev/null | awk -F: -v name="\$sandbox_name" '\$3 == name { found = 1 } END { exit found ? 0 : 1 }'; then
      printf 'Error: IP address 10.0.1.2 is already in use\n' >&2
      exit 1
    fi
  fi
fi

exec "\$real_firejail" "\$@"
SH
    chmod +x "${fixture}/firejail"
}

profile_start_count() {
    if [ ! -e "$firejail_wrapper_log" ]; then
        printf '0\n'
        return
    fi

    awk '/^PROFILE_START / { count++ } END { print count + 0 }' "$firejail_wrapper_log"
}

assert_no_ip_conflict_error() {
    if grep -Fq 'Error: IP address 10.0.1.2 is already in use' "$@"; then
        printf 'parallel sandbox startup hit the static-IP race:\n' >&2
        cat "$@" >&2
        exit 1
    fi
}

assert_fake_wine_ran_inside_firejail() {
    grep -Fxq 'INSIDE_FIREJAIL=1' "$fake_wine_log"
}

assert_fake_wine_did_not_run() {
    [ ! -e "$fake_wine_log" ] || {
        printf 'fake wine unexpectedly ran:\n' >&2
        cat "$fake_wine_log" >&2
        exit 1
    }
}

assert_profile_checker_ran() {
    [ -s "$checker_log" ] || {
        printf 'expected fj-profile-checker wrapper to run\n' >&2
        exit 1
    }
    grep -Fq "$sandbox_check_profile" "$checker_log"
}

install_logrotate_config() {
    local config_home="${XDG_CONFIG_HOME:-$home/.config}"
    local state_root="${XDG_STATE_HOME:-$home/.local/state}/wine-apps"

    mkdir -p "${config_home}/logrotate"
    cat >"${config_home}/logrotate/wine-apps.conf" <<CONF
${state_root}/*/*.log {
    size 20M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
CONF
}

case "${DOTFILES_TEST_CASE:-}" in
wwine-prepare-env-exports-sandbox-loader)
    make_fixture

    run_wwine --prefix reaper --no-desktop --use-sandbox prepare-env >"$output"
    grep -Fxq "export WINEPREFIX=$wine_prefix" "$output"
    grep -Fxq "export WINELOADER=$wwine_loader" "$output"
    grep -Fxq "export WWINE_USE_SANDBOX=1" "$output"
    grep -Fxq "export WWINE_SANDBOX_PROFILE=$sandbox_profile" "$output"
    grep -Fxq "export WWINE_SANDBOX_CHECK_PROFILE=$sandbox_check_profile" "$output"
    grep -Fxq "export WWINE_SANDBOX_NAME=$sandbox_name" "$output"
    ;;
wwine-use-sandbox-starts-real-firejail-and-checks-profile)
    make_fixture
    trap shutdown_sandbox EXIT

    run_wwine --prefix reaper --no-desktop --use-sandbox wine marker
    assert_fake_wine_ran_inside_firejail
    assert_profile_checker_ran
    grep -Fq 'ARGS=<reg><delete><HKEY_CURRENT_USER\Software\Wine\Explorer><' "$fake_wine_log"
    grep -Fxq 'ARGS=<marker>' "$fake_wine_log"
    ;;
wwine-log-id-rotates-and-captures-output-before-sandbox)
    make_fixture
    install_logrotate_config
    trap shutdown_sandbox EXIT

    run_wwine --prefix reaper --use-sandbox --log-id reaper wine emit-output

    state_root="${XDG_STATE_HOME:-$home/.local/state}/wine-apps"
    config_home="${XDG_CONFIG_HOME:-$home/.config}"
    app_log="${state_root}/reaper/reaper.log"
    [ -s "$fake_logrotate_log" ]
    grep -Fq "<-s><${state_root}/logrotate.status><${config_home}/logrotate/wine-apps.conf>" "$fake_logrotate_log"
    grep -Fxq "FAKE_WINE_STDOUT=1" "$app_log"
    grep -Fxq "FAKE_WINE_STDERR=1" "$app_log"
    assert_fake_wine_ran_inside_firejail
    assert_profile_checker_ran
    ;;
wwine-wine-loader-mode-starts-real-firejail-and-preserves-args)
    make_fixture
    trap shutdown_sandbox EXIT

    run_loader loader-arg 'arg with spaces'
    assert_fake_wine_ran_inside_firejail
    assert_profile_checker_ran
    grep -Fxq 'ARGS=<loader-arg><arg with spaces>' "$fake_wine_log"
    ;;
wwine-reuses-existing-named-firejail-sandbox)
    make_fixture
    trap shutdown_sandbox EXIT

    firejail --quiet --profile="$sandbox_profile" --join-or-start="$sandbox_name" \
        env -i HOME="$home" PATH="${fixture}:/usr/bin:/bin" sh -c "touch '$fixture/sandbox-ready'; while [ ! -e '$fixture/stop-sandbox' ]; do sleep 0.05; done" &
    wait_for_sandbox

    run_wwine --prefix reaper --no-desktop --use-sandbox wine joined
    assert_fake_wine_ran_inside_firejail
    assert_profile_checker_ran
    grep -Fxq 'ARGS=<joined>' "$fake_wine_log"
    [ "$(firejail --list 2>/dev/null | awk -F: -v name="$sandbox_name" '$3 == name { count++ } END { print count + 0 }')" -eq 1 ]
    touch "${fixture}/stop-sandbox"
    ;;
wwine-serializes-parallel-named-sandbox-startup)
    make_fixture
    install_firejail_race_wrapper
    touch "${fixture}/simulate-firejail-race"
    first_output="${fixture}/first-wwine.out"
    second_output="${fixture}/second-wwine.out"
    first_pid=""
    second_pid=""
    trap 'touch "${fixture}/allow-first-firejail" "${fixture}/stop-fake-wine" 2>/dev/null || true; shutdown_sandbox; [ -n "$first_pid" ] && wait "$first_pid" 2>/dev/null || true; [ -n "$second_pid" ] && wait "$second_pid" 2>/dev/null || true' EXIT

    run_wwine --prefix reaper --no-desktop --use-sandbox wine hold-sandbox >"$first_output" 2>&1 &
    first_pid=$!
    wait_for_file "${fixture}/first-firejail-blocked" "first delayed Firejail startup"

    run_wwine --prefix reaper --no-desktop --use-sandbox wine parallel-join >"$second_output" 2>&1 &
    second_pid=$!
    sleep 0.25

    [ "$(profile_start_count)" -eq 1 ] || {
        printf 'second wwine reached firejail before the first sandbox was published:\n' >&2
        cat "$firejail_wrapper_log" >&2
        exit 1
    }
    assert_no_ip_conflict_error "$first_output" "$second_output" "$firejail_wrapper_log"

    touch "${fixture}/allow-first-firejail"
    wait_for_sandbox
    wait_for_file "${fixture}/fake-wine-holding" "holding fake Wine process"

    wait "$second_pid"
    second_pid=""
    assert_no_ip_conflict_error "$first_output" "$second_output" "$firejail_wrapper_log"
    [ "$(profile_start_count)" -eq 2 ]
    grep -Fxq 'ARGS=<parallel-join>' "$fake_wine_log"
    [ "$(firejail --list 2>/dev/null | awk -F: -v name="$sandbox_name" '$3 == name { count++ } END { print count + 0 }')" -eq 1 ]

    touch "${fixture}/stop-fake-wine"
    wait "$first_pid"
    first_pid=""
    ;;
wwine-fails-closed-when-inherited-sandbox-does-not-match-profile)
    make_fixture

    if HOME="$home" XDG_RUNTIME_DIR="$runtime" PATH="${fixture}:/usr/bin:/bin" \
        firejail --quiet --profile="$writable_sandbox_profile" -- \
        "$rendered" --prefix reaper --no-desktop --use-sandbox wine should-not-run >"$output" 2>&1; then
        printf 'wwine unexpectedly accepted mismatched inherited sandbox\n' >&2
        exit 1
    fi

    assert_fake_wine_did_not_run
    grep -Fq 'sandbox exposes read-only path as writable' "$output"
    assert_profile_checker_ran
    ;;
wwine-no-desktop-closes-running-wine-desktop-before-app)
    make_fixture

    run_wwine --prefix reaper --desktop wine start-desktop
    run_wwine --prefix reaper --no-desktop wine launch-after-desktop

    grep -Fq 'ARGS=<reg><delete><HKEY_CURRENT_USER\Software\Wine\Explorer><' "$fake_wine_log"
    grep -Fxq 'ARGS=<taskkill></F></IM><explorer.exe>' "$fake_wine_log"
    grep -Fxq 'OPENED_IN_DESKTOP=0' "$fake_wine_log"
    ;;
wwine-no-desktop-taskkill-is-prefix-scoped)
    make_fixture

    run_wwine --prefix "$other_wine_prefix" --arch win64 --desktop wine start-desktop
    run_wwine --prefix reaper --no-desktop wine launch-after-desktop

    [ -e "${fixture}/active-wine-desktop-other" ]
    [ ! -e "${fixture}/active-wine-desktop-reaper" ]
    grep -Fxq "WINEPREFIX=$other_wine_prefix" "$fake_wine_log"
    grep -Fxq "WINEPREFIX=$wine_prefix" "$fake_wine_log"
    grep -Fxq 'OPENED_IN_DESKTOP=0' "$fake_wine_log"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
