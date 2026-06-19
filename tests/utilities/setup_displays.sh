#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities displays shell firejail
# dotfiles-test-case: setup-displays-syntax
# dotfiles-test-case: setup-displays-external-replaces-internal
# dotfiles-test-case: setup-displays-external-inactive-enables-external
# dotfiles-test-case: setup-displays-external-prime-name-enables-external
# dotfiles-test-case: setup-displays-no-external-restores-internal
# dotfiles-test-case: setup-displays-external-failure-tries-auto
# dotfiles-test-case: setup-displays-toggle-internal-to-external
# dotfiles-test-case: setup-displays-toggle-external-to-internal
# dotfiles-test-case: setup-displays-toggle-external-to-internal-refreshes-healthy-scanout
# dotfiles-test-case: setup-displays-toggle-external-to-internal-repairs-stale-scanout
# dotfiles-test-case: setup-displays-toggle-restarts-compositor
# dotfiles-test-case: setup-displays-auto-keeps-compositor
# dotfiles-test-case: setup-displays-toggle-internal-to-external-saves-backlight
# dotfiles-test-case: setup-displays-toggle-external-to-internal-restores-backlight

# Purpose: Verify the XRandR display layout policy and manual toggle managed by setup-displays.sh.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/setup-displays.sh"

make_fake_path() {
    local bin=$1

    mkdir -p "$bin"
    ln -s /usr/bin/bash "${bin}/bash"
    ln -s /usr/bin/awk "${bin}/awk"
    ln -s /usr/bin/cat "${bin}/cat"
    ln -s /usr/bin/grep "${bin}/grep"
    ln -s /usr/bin/mkdir "${bin}/mkdir"
    ln -s /usr/bin/sed "${bin}/sed"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${bin}/sleep"
    printf '#!/usr/bin/env bash\nprintf "xset %%s\\n" "$*" >>"${DOTFILES_TEST_TMP}/xset.log"\n' >"${bin}/xset"
    printf '#!/usr/bin/env bash\nprintf "apply-wallpaper\\n" >>"${DOTFILES_TEST_TMP}/apply-wallpaper.log"\n' >"${bin}/apply-wallpaper"
    printf '#!/usr/bin/env bash\nprintf "systemctl %%s\\n" "$*" >>"${DOTFILES_TEST_TMP}/systemctl.log"\nexit 0\n' >"${bin}/systemctl"
    chmod +x "${bin}/sleep"
    chmod +x "${bin}/xset"
    chmod +x "${bin}/apply-wallpaper"
    chmod +x "${bin}/systemctl"
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
external-inactive | external-prime-name)
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
external-only)
    case "$*" in
    --query)
        printf '%s\n' \
            'eDP-1 connected' \
            '   1920x1080     60.00' \
            'HDMI-1 connected primary 3440x1440+0+0' \
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
external-only-stale-internal)
    case "$*" in
    --query)
        if [[ -r "${DOTFILES_TEST_TMP}/xrandr-state" ]]; then
            printf '%s\n' \
                'eDP-1 connected primary 1920x1080+0+0' \
                '   1920x1080f    120.21*  60.00' \
                '   1920x1080     60.00' \
                'HDMI-1 connected' \
                '   3440x1440     59.97'
        else
            printf '%s\n' \
                'eDP-1 connected' \
                '   1920x1080     60.00' \
                'HDMI-1 connected primary 3440x1440+0+0' \
                '   3440x1440     59.97*'
        fi
        ;;
    --listmonitors)
        printf '%s\n' \
            'Monitors: 1' \
            ' 0: +*HDMI-1 3440/800x1440/330+0+0 HDMI-1'
        ;;
    --output\ eDP-1\ --primary\ --mode\ 1920x1080f\ --rate\ 120.21\ --pos\ 0x0\ --output\ HDMI-1\ --off)
        printf '%s\n' "$*" >>"$log"
        printf 'internal-stale\n' >"${DOTFILES_TEST_TMP}/xrandr-state"
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
    *--output\ HDMI-1\ --primary*)
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

write_fake_backlight() {
    local brightness=$1
    local backlight="${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1/amdgpu_bl1"

    mkdir -p "$backlight"
    printf '%s\n' "$brightness" >"$backlight/brightness"
    printf '%s\n' 65535 >"$backlight/max_brightness"
}

write_fake_stale_internal_scanout() {
    local drm="${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1"

    mkdir -p "$drm"
    printf '%s\n' connected >"$drm/status"
    printf '%s\n' disabled >"$drm/enabled"
    printf '%s\n' Off >"$drm/dpms"
}

run_setup_displays() {
    local scenario=$1
    local mode=${2:-}
    local bin="${DOTFILES_TEST_TMP}/bin"

    make_fake_path "$bin"
    write_fake_xrandr "$bin"
    XRANDR_SCENARIO="$scenario" PATH="$bin" HOME="${DOTFILES_TEST_TMP}/home" XDG_RUNTIME_DIR="${DOTFILES_TEST_TMP}/runtime" SETUP_DISPLAYS_SYSFS_ROOT="${DOTFILES_TEST_TMP}/sys" "$script_under_test" $mode >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"
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
    assert_log_equals "--output eDP-1 --off --output HDMI-1 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-external-inactive-enables-external)
    run_setup_displays external-inactive
    assert_log_equals "--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-external-prime-name-enables-external)
    run_setup_displays external-prime-name
    assert_log_equals "--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-no-external-restores-internal)
    run_setup_displays internal
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21 --pos 0x0"
    ;;
setup-displays-external-failure-tries-auto)
    run_setup_displays external-fails
    assert_log_equals "--output eDP-1 --off --output HDMI-1 --primary --mode 3440x1440 --rate 59.97 --pos 0x0
--output eDP-1 --off --output HDMI-1 --primary --auto --pos 0x0"
    ;;
setup-displays-toggle-internal-to-external)
    run_setup_displays external-inactive --toggle
    assert_log_equals "--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    ;;
setup-displays-toggle-external-to-internal)
    run_setup_displays external-only --toggle
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21 --pos 0x0 --output HDMI-1 --off"
    ;;
setup-displays-toggle-external-to-internal-refreshes-healthy-scanout)
    run_setup_displays external-only-stale-internal --toggle
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21 --pos 0x0 --output HDMI-1 --off
--output eDP-1 --mode 1920x1080f --rate 60.00
--output eDP-1 --mode 1920x1080f --rate 120.21"
    grep -q '^xset dpms force on$' "${DOTFILES_TEST_TMP}/xset.log"
    if grep -q 'scanout looks stale' "${DOTFILES_TEST_TMP}/stderr"; then
        printf 'healthy scanout refresh should not report stale DRM state\n' >&2
        exit 1
    fi
    ;;
setup-displays-toggle-external-to-internal-repairs-stale-scanout)
    write_fake_stale_internal_scanout
    run_setup_displays external-only-stale-internal --toggle
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21 --pos 0x0 --output HDMI-1 --off
--output eDP-1 --mode 1920x1080f --rate 60.00
--output eDP-1 --mode 1920x1080f --rate 120.21"
    grep -q '^xset dpms force on$' "${DOTFILES_TEST_TMP}/xset.log"
    grep -q 'eDP-1 scanout looks stale after layout toggle; refreshing mode' "${DOTFILES_TEST_TMP}/stderr"
    ;;
setup-displays-toggle-restarts-compositor)
    run_setup_displays external-only --toggle
    grep -q '^systemctl --user restart compositor.service$' "${DOTFILES_TEST_TMP}/systemctl.log"
    ;;
setup-displays-auto-keeps-compositor)
    run_setup_displays internal
    if grep -qs 'restart compositor.service' "${DOTFILES_TEST_TMP}/systemctl.log"; then
        printf 'auto path must not restart the compositor\n' >&2
        exit 1
    fi
    ;;
setup-displays-toggle-internal-to-external-saves-backlight)
    write_fake_backlight 40000
    run_setup_displays external-inactive --toggle
    assert_log_equals "--output eDP-1 --off --output HDMI-1-0 --primary --mode 3440x1440 --rate 59.97 --pos 0x0"
    grep -q '^40000$' "${DOTFILES_TEST_TMP}/runtime/setup-displays/internal-brightness"
    ;;
setup-displays-toggle-external-to-internal-restores-backlight)
    write_fake_backlight 80
    mkdir -p "${DOTFILES_TEST_TMP}/runtime/setup-displays"
    printf '%s\n' 80 >"${DOTFILES_TEST_TMP}/runtime/setup-displays/internal-brightness"
    run_setup_displays external-only --toggle
    assert_log_equals "--newmode 1920x1080f 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync
--addmode eDP-1 1920x1080f
--output eDP-1 --primary --mode 1920x1080f --rate 120.21 --pos 0x0 --output HDMI-1 --off"
    grep -q '^32767$' "${DOTFILES_TEST_TMP}/sys/class/drm/card1-eDP-1/amdgpu_bl1/brightness"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
