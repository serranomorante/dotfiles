#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities displays ddc shell firejail
# dotfiles-test-case: monitor-power-watch-syntax
# dotfiles-test-case: monitor-power-watch-initial-on-does-not-apply
# dotfiles-test-case: monitor-power-watch-off-to-on-applies-once
# dotfiles-test-case: monitor-power-watch-on-to-off-applies-once
# dotfiles-test-case: monitor-power-watch-transient-on-does-not-apply
# dotfiles-test-case: monitor-power-watch-on-without-drm-connector-applies
# dotfiles-test-case: monitor-power-watch-udev-does-not-trigger-setup-displays

# Purpose: Verify DDC power-state transition behavior for monitor-power-watch.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/monitor-power-watch"

make_fake_path() {
    local bin=$1

    mkdir -p "$bin"
    ln -s /usr/bin/bash "${bin}/bash"
    ln -s /usr/bin/awk "${bin}/awk"
    ln -s /usr/bin/cat "${bin}/cat"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${bin}/sleep"
    chmod +x "${bin}/sleep"
}

write_fake_ddcutil() {
    local bin=$1

    cat >"${bin}/ddcutil" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
detect\ --brief)
    if [[ "${MONITOR_POWER_WATCH_TEST_NO_DRM_CONNECTOR:-0}" == "1" ]]; then
        printf '%s\n' \
            'Display 1' \
            '   I2C bus:          /dev/i2c-8' \
            '   drm_connector_id: 0' \
            '   Monitor:          GSM:LG HDR WQHD:'
    else
        printf '%s\n' \
            'Display 1' \
            '   I2C bus:          /dev/i2c-8' \
            '   DRM connector:    card0-HDMI-A-1' \
            '   Monitor:          GSM:LG HDR WQHD:'
    fi
    ;;
--bus\ 8\ getvcp\ D6)
    index_file="${DOTFILES_TEST_TMP}/ddc-index"
    index=$(cat "$index_file" 2>/dev/null || printf '0')
    IFS=',' read -ra states <<<"${MONITOR_POWER_WATCH_TEST_STATES}"
    if [[ "$index" -ge "${#states[@]}" ]]; then
        index=$((${#states[@]} - 1))
    fi
    state="${states[$index]}"
    printf '%s\n' "$((index + 1))" >"$index_file"

    case "$state" in
    on)
        printf '%s\n' 'VCP code 0xd6 (Power mode                    ): DPM: On,  DPMS: Off (sl=0x01)'
        ;;
    off)
        printf '%s\n' 'VCP code 0xd6 (Power mode                    ): Write only value to turn off display (sl=0x05)'
        ;;
    *)
        printf '%s\n' 'VCP code 0xd6 (Power mode                    ): unknown'
        ;;
    esac
    ;;
*)
    printf 'unexpected ddcutil call: %s\n' "$*" >&2
    exit 2
    ;;
esac
BASH
    chmod +x "${bin}/ddcutil"
}

write_fake_setup() {
    local path=$1

    cat >"$path" <<'BASH'
#!/usr/bin/env bash
printf 'setup\n' >>"${DOTFILES_TEST_TMP}/setup.log"
BASH
    chmod +x "$path"
}

run_watch() {
    local states=$1
    local iterations=$2
    local no_drm_connector=${3:-0}
    local bin="${DOTFILES_TEST_TMP}/bin"
    local setup="${DOTFILES_TEST_TMP}/setup-displays.sh"

    make_fake_path "$bin"
    write_fake_ddcutil "$bin"
    write_fake_setup "$setup"

    MONITOR_POWER_WATCH_TEST_STATES="$states" \
        MONITOR_POWER_WATCH_TEST_NO_DRM_CONNECTOR="$no_drm_connector" \
        MONITOR_POWER_WATCH_INTERVAL=5 \
        MONITOR_POWER_WATCH_MAX_ITERATIONS="$iterations" \
        MONITOR_POWER_WATCH_SETUP="$setup" \
        PATH="$bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        "$script_under_test" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"
}

assert_setup_count() {
    local expected=$1
    local actual

    if [[ -f "${DOTFILES_TEST_TMP}/setup.log" ]]; then
        actual=$(wc -l <"${DOTFILES_TEST_TMP}/setup.log")
    else
        actual=0
    fi
    if [[ "$actual" != "$expected" ]]; then
        printf 'expected %s setup calls, got %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
monitor-power-watch-syntax)
    bash -n "$script_under_test"
    ;;
monitor-power-watch-initial-on-does-not-apply)
    run_watch on,on 2
    assert_setup_count 0
    ;;
monitor-power-watch-off-to-on-applies-once)
    run_watch off,on,on 3
    assert_setup_count 1
    grep -q "external monitor power changed: off -> on" "${DOTFILES_TEST_TMP}/stderr"
    ;;
monitor-power-watch-on-to-off-applies-once)
    run_watch on,off,off 3
    assert_setup_count 1
    grep -q "external monitor power changed: on -> off" "${DOTFILES_TEST_TMP}/stderr"
    ;;
monitor-power-watch-transient-on-does-not-apply)
    run_watch off,on,off 3
    assert_setup_count 0
    ;;
monitor-power-watch-on-without-drm-connector-applies)
    run_watch off,on,on 3 1
    assert_setup_count 1
    grep -q "external monitor power changed: off -> on" "${DOTFILES_TEST_TMP}/stderr"
    ;;
monitor-power-watch-udev-does-not-trigger-setup-displays)
    if grep -q "setup-displays.service" "${DOTFILES_TEST_ROOT}/assets/udev-rules/95-monitor-hotplug.rules"; then
        printf 'udev must not trigger setup-displays.service\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
