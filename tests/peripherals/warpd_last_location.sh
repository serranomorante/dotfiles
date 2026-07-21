#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: peripherals
# dotfiles-test-tags: peripherals warpd keyd shell fast firejail
# dotfiles-test-case: warpd-last-location-syntax
# dotfiles-test-case: warpd-last-location-keyd-contract
# dotfiles-test-case: warpd-last-location-history-navigation
# dotfiles-test-case: warpd-last-location-history-size

# Purpose: Verify the warpd cursor location toggle/history helper and keyd integration.

script_under_test="${DOTFILES_TEST_ROOT}/peripherals/bin/warpd-last-location"
keyd_observer="${DOTFILES_TEST_ROOT}/peripherals/bin/keyd-observer"
keyd_template="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/templates/keyd-default.conf"

assert_eq() {
    local expected=$1 actual=$2 label=$3

    [[ "$actual" == "$expected" ]] || {
        printf 'expected %s to be <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    }
}

assert_file_exact() {
    local file=$1 expected=$2 label=$3 actual

    actual=$(cat "$file")
    assert_eq "$expected" "$actual" "$label"
}

make_fake_warpd_fixture() {
    fixture="${DOTFILES_TEST_TMP}/warpd-last-location"
    fake_bin="${fixture}/bin"
    runtime="${fixture}/runtime"
    home="${fixture}/home"
    current_file="${fixture}/current"
    target_file="${fixture}/target"
    move_log="${fixture}/moves.log"

    mkdir -p "$fake_bin" "$runtime" "$home/bin"
    printf '0 0\n' >"$current_file"
    printf '1000 1000\n' >"$target_file"
    : >"$move_log"

    cat >"${fake_bin}/xdotool" <<'SH'
#!/usr/bin/env sh
case "$1" in
getmouselocation)
    read -r x y <"$TEST_CURRENT_FILE"
    printf 'X=%s\nY=%s\n' "$x" "$y"
    ;;
*)
    exit 2
    ;;
esac
SH

    cat >"${fake_bin}/warpd" <<'SH'
#!/usr/bin/env sh
case "$1" in
--config)
    sleep 0.05
    read -r x y <"$TEST_TARGET_FILE"
    printf '%s %s\n' "$x" "$y"
    printf '%s %s\n' "$x" "$y" >"$TEST_CURRENT_FILE"
    ;;
--move)
    printf '%s\n' "$2" >"$TEST_CURRENT_FILE"
    printf '%s\n' "$2" >>"$TEST_MOVE_LOG"
    ;;
*)
    exit 2
    ;;
esac
SH
    chmod +x "${fake_bin}/xdotool" "${fake_bin}/warpd"
}

run_warpd_last_location() {
    local history_size=${WARPD_TEST_HISTORY_SIZE:-10}

    HOME="$home" \
        XDG_RUNTIME_DIR="$runtime" \
        PATH="${fake_bin}:$PATH" \
        TEST_CURRENT_FILE="$current_file" \
        TEST_TARGET_FILE="$target_file" \
        TEST_MOVE_LOG="$move_log" \
        WARPD_TRAIL=/bin/false \
        WARPD_LAST_LOCATION_HISTORY_SIZE="$history_size" \
        "$script_under_test" "$@"
}

set_current() {
    printf '%s %s\n' "$1" "$2" >"$current_file"
}

set_target() {
    printf '%s %s\n' "$1" "$2" >"$target_file"
}

current_xy() {
    cat "$current_file"
}

history_file() {
    printf '%s/warpd-last-location/history\n' "$runtime"
}

case "${DOTFILES_TEST_CASE:-}" in
warpd-last-location-syntax)
    sh -n "$script_under_test"
    sh -n "$keyd_observer"
    ;;
warpd-last-location-keyd-contract)
    rg -q '^\[signal_warpd_history_back\]$' "$keyd_template"
    rg -q '^\[signal_warpd_history_forward\]$' "$keyd_template"
    rg -q '^g = layer\(signal_toggle_warpd_last_location\)$' "$keyd_template"
    rg -q '^o = layer\(signal_warpd_history_back\)$' "$keyd_template"
    rg -q '^i = layer\(signal_warpd_history_forward\)$' "$keyd_template"
    rg -q '^r = toggle\(readline\)$' "$keyd_template"
    ! rg -q '^i = toggle\(readline\)$' "$keyd_template"
    rg -q '^\s*\+signal_warpd_history_back\)$' "$keyd_observer"
    rg -q '^\s*\+signal_warpd_history_forward\)$' "$keyd_observer"
    rg -q 'run_warpd_last_location back' "$keyd_observer"
    rg -q 'run_warpd_last_location forward' "$keyd_observer"
    ;;
warpd-last-location-history-navigation)
    make_fake_warpd_fixture
    set_current 0 0
    set_target 1000 1000
    run_warpd_last_location run-hint
    set_target 2000 2000
    run_warpd_last_location run-hint

    run_warpd_last_location back
    assert_eq '1000 1000' "$(current_xy)" 'first history back jump'
    run_warpd_last_location back
    assert_eq '0 0' "$(current_xy)" 'second history back jump'
    run_warpd_last_location back
    assert_eq '0 0' "$(current_xy)" 'non-cyclic history back limit'
    run_warpd_last_location forward
    assert_eq '1000 1000' "$(current_xy)" 'history forward jump'

    set_current 3500 3500
    run_warpd_last_location back
    assert_eq '1000 1000' "$(current_xy)" 'manual movement branches history before back'
    run_warpd_last_location forward
    assert_eq '3500 3500' "$(current_xy)" 'forward reaches manual branch point'
    assert_file_exact "$(history_file)" $'0 0\n1000 1000\n3500 3500' 'branched history contents'
    ;;
warpd-last-location-history-size)
    make_fake_warpd_fixture
    set_current 0 0
    WARPD_TEST_HISTORY_SIZE=12
    export WARPD_TEST_HISTORY_SIZE
    for i in {1..14}; do
        set_target "$((i * 1000))" "$((i * 1000))"
        run_warpd_last_location run-hint
    done

    count=$(wc -l <"$(history_file)")
    first=$(sed -n '1p' "$(history_file)")
    last=$(sed -n "${count}p" "$(history_file)")
    assert_eq '12' "$count" 'configurable history size'
    assert_eq '3000 3000' "$first" 'oldest retained history entry'
    assert_eq '14000 14000' "$last" 'newest retained history entry'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
