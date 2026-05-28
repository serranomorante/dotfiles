#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities displays ddc shell firejail
# dotfiles-test-case: setup-displays-syntax
# dotfiles-test-case: setup-displays-external-replaces-internal
# dotfiles-test-case: setup-displays-ddc-on-enables-external
# dotfiles-test-case: setup-displays-ddc-on-without-drm-enables-external
# dotfiles-test-case: setup-displays-ddc-off-keeps-internal
# dotfiles-test-case: setup-displays-no-external-restores-internal
# dotfiles-test-case: setup-displays-external-failure-keeps-internal

# Purpose: Verify the DDC-gated display layout policy managed by setup-displays.sh.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/setup-displays.sh"

make_fake_path() {
    local bin=$1

    mkdir -p "$bin"
    ln -s /usr/bin/bash "${bin}/bash"
    ln -s /usr/bin/awk "${bin}/awk"
    ln -s /usr/bin/grep "${bin}/grep"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${bin}/sleep"
    chmod +x "${bin}/sleep"
}

write_fake_xrandr() {
    local bin=$1

    cat >"${bin}/xrandr" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

log="${DOTFILES_TEST_TMP}/xrandr.log"

case "${XRANDR_SCENARIO}" in
external)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected primary 1920x1080+0+0' \
            '   1920x1080     60.00*' \
            'HDMI-1 connected 3440x1440+0+0' \
            '   3440x1440     59.97*'
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 1' \
            ' 0: +*HDMI-1 3440/800x1440/330+0+0 HDMI-1'
        ;;
    *)
        printf '%s\n' "$*" >>"$log"
        ;;
    esac
    ;;
external-inactive | external-inactive-no-drm)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected primary 1920x1080+0+0' \
            '   1920x1080     60.00*' \
            'HDMI-1-0 connected' \
            '   3440x1440     59.97 +  49.99    29.99'
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 1' \
            ' 0: +*eDP-1 1920/340x1080/190+0+0 eDP-1'
        ;;
    --output\ HDMI-1-0\ --primary*)
        printf '%s\n' "$*" >>"$log"
        ;;
    *)
        printf '%s\n' "$*" >>"$log"
        ;;
    esac
    ;;
external-off)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected primary 1920x1080+0+0' \
            '   1920x1080     60.00*' \
            'HDMI-1-0 connected primary 3440x1440+0+0' \
            '   3440x1440     59.97*+'
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 2' \
            ' 0: +eDP-1 1920/340x1080/190+0+0 eDP-1' \
            ' 1: +*HDMI-1-0 3440/800x1440/335+0+0 HDMI-1-0'
        ;;
    *)
        printf '%s\n' "$*" >>"$log"
        ;;
    esac
    ;;
internal)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected primary 1920x1080+0+0' \
            '   1920x1080     60.00*' \
            'HDMI-1 disconnected'
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 1' \
            ' 0: +*eDP-1 1920/340x1080/190+0+0 eDP-1'
        ;;
    *)
        printf '%s\n' "$*" >>"$log"
        ;;
    esac
    ;;
external-fails)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected primary 1920x1080+0+0' \
            '   1920x1080     60.00*' \
            'HDMI-1 connected 3440x1440+0+0' \
            '   3440x1440     59.97*'
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 1' \
            ' 0: +*eDP-1 1920/340x1080/190+0+0 eDP-1'
        ;;
    --output\ HDMI-1\ --primary*)
        printf '%s\n' "$*" >>"$log"
        exit 1
        ;;
    *)
        printf '%s\n' "$*" >>"$log"
        ;;
    esac
    ;;
*)
    printf 'unknown XRANDR_SCENARIO: %s\n' "${XRANDR_SCENARIO}" >&2
    exit 2
    ;;
esac
BASH
    chmod +x "${bin}/xrandr"
}

write_fake_ddcutil() {
    local bin=$1

    cat >"${bin}/ddcutil" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
detect\ --brief)
    if [[ "${XRANDR_SCENARIO}" == "external-inactive-no-drm" ]]; then
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
    case "${XRANDR_SCENARIO}" in
    external-off)
        printf '%s\n' 'VCP code 0xd6 (Power mode                    ): Write only value to turn off display (sl=0x05)'
        ;;
    *)
        printf '%s\n' 'VCP code 0xd6 (Power mode                    ): DPM: On,  DPMS: Off (sl=0x01)'
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

run_setup_displays() {
    local scenario=$1
    local bin="${DOTFILES_TEST_TMP}/bin"

    make_fake_path "$bin"
    write_fake_xrandr "$bin"
    write_fake_ddcutil "$bin"
    XRANDR_SCENARIO="$scenario" PATH="$bin" HOME="${DOTFILES_TEST_TMP}/home" "$script_under_test" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"
}

assert_log_equals() {
    local expected=$1

    printf '%s\n' "$expected" >"${DOTFILES_TEST_TMP}/expected.log"
    touch "${DOTFILES_TEST_TMP}/xrandr.log"
    if ! diff -u "${DOTFILES_TEST_TMP}/expected.log" "${DOTFILES_TEST_TMP}/xrandr.log"; then
        printf 'unexpected xrandr calls\n' >&2
        exit 1
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
setup-displays-syntax)
    bash -n "$script_under_test"
    ;;
setup-displays-external-replaces-internal)
    run_setup_displays external
    assert_log_equals "--output HDMI-1 --primary --mode 3440x1440 --rate 59.97 --right-of eDP-1
--output eDP-1 --off --output HDMI-1 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-ddc-on-enables-external)
    run_setup_displays external-inactive
    assert_log_equals "--output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --right-of eDP-1
--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-ddc-on-without-drm-enables-external)
    run_setup_displays external-inactive-no-drm
    assert_log_equals "--output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --right-of eDP-1
--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-ddc-off-keeps-internal)
    run_setup_displays external-off
    assert_log_equals "--output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --right-of eDP-1
--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21
--output HDMI-1-0 --off"
    grep -q "external monitor HDMI-1-0 is not powered on; keeping eDP-1 active" "${DOTFILES_TEST_TMP}/stderr"
    ;;
setup-displays-no-external-restores-internal)
    run_setup_displays internal
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21"
    ;;
setup-displays-external-failure-keeps-internal)
    run_setup_displays external-fails
    assert_log_equals "--output HDMI-1 --primary --mode 3440x1440 --rate 59.97 --right-of eDP-1
--output HDMI-1 --primary --auto --right-of eDP-1
--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21
--output HDMI-1 --off"
    grep -q "external monitor HDMI-1 is not powered on; keeping eDP-1 active" "${DOTFILES_TEST_TMP}/stderr"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
