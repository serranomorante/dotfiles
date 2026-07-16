#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities vim-registers kitty fzf xclip xdotool shell
# dotfiles-test-case: vim-register-picker-syntax
# dotfiles-test-case: vim-register-picker-panel-pick-pastes-selection

# Purpose: Verify the global Vim register picker list, selection, and paste handoff.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/vim-register-picker"

make_fake_path() {
    local bin="${DOTFILES_TEST_TMP}/bin"

    mkdir -p "$bin"
    cat >"${bin}/cachectl" <<'SH'
#!/usr/bin/env sh
set -eu

if [ "$1" != get ] || [ "$2" != vim-registers ]; then
    printf 'unexpected cachectl call: %s\n' "$*" >&2
    exit 2
fi

case "$3" in
a)
    printf 'alpha register line 1\nalpha register line 2\n'
    ;;
b)
    printf 'bravo register'
    ;;
unnamed | small-delete | plus | star | [c-z] | [0-9])
    exit 1
    ;;
*)
    printf 'unexpected register key: %s\n' "$3" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/cachectl"
    cat >"${bin}/kitten" <<'SH'
#!/usr/bin/env sh
set -eu

case "$1" in
quick-access-terminal)
    shift
    while [ "$#" -gt 0 ]; do
        case $1 in
        env)
            shift
            printf 'panel-start\n' >>"${DOTFILES_TEST_TMP}/events.log"
            env "$@"
            status=$?
            touch "${DOTFILES_TEST_TMP}/panel-closed"
            printf 'panel-closed\n' >>"${DOTFILES_TEST_TMP}/events.log"
            exit "$status"
            ;;
        --instance-group=* | --detach=*)
            shift
            ;;
        --detach)
            shift
            ;;
        --override)
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    exit 2
    ;;
*)
    exec "$@"
    ;;
esac
SH
    chmod +x "${bin}/kitten"
    cat >"${bin}/fzf" <<'SH'
#!/usr/bin/env sh
set -eu

input_file="${DOTFILES_TEST_TMP}/fzf-input"
args_file="${DOTFILES_TEST_TMP}/fzf-args"
printf '%s\n' "$@" >"$args_file"
cat >"$input_file"
grep '^a	' "$input_file"
SH
    chmod +x "${bin}/fzf"
    cat >"${bin}/xclip" <<'SH'
#!/usr/bin/env sh
set -eu

cat >"${DOTFILES_TEST_TMP}/clipboard.txt"
printf 'xclip\n' >>"${DOTFILES_TEST_TMP}/events.log"
SH
    chmod +x "${bin}/xclip"
    cat >"${bin}/xdotool" <<'SH'
#!/usr/bin/env sh
set -eu

case "$*" in
"getactivewindow")
    count_file="${DOTFILES_TEST_TMP}/active-window-count"
    if [ -f "$count_file" ]; then
        count=$(cat "$count_file")
    else
        count=0
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"

    if [ ! -e "${DOTFILES_TEST_TMP}/panel-closed" ]; then
        printf '%s\n' 1000
    elif [ "$count" -lt 2 ]; then
        printf 'focus-still-picker\n' >>"${DOTFILES_TEST_TMP}/events.log"
        printf '%s\n' 1000
    else
        printf '%s\n' 2000
    fi
    ;;
"getwindowclassname 1000")
    printf '%s\n' kitty-vim-registers
    ;;
"getwindowclassname 2000")
    printf '%s\n' kitty
    ;;
"key --clearmodifiers ctrl+shift+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-terminal\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
"key --clearmodifiers ctrl+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-browser\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
*)
    printf 'unexpected xdotool call: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/xdotool"
    printf '%s\n' "$bin"
}

wait_for_file() {
    local path=$1
    local attempts=${2:-200}
    local attempt

    for ((attempt = 0; attempt < attempts; attempt++)); do
        [ -e "$path" ] && return 0
        sleep 0.05
    done

    return 1
}

case "${DOTFILES_TEST_CASE:-}" in
vim-register-picker-syntax)
    sh -n "$script_under_test"
    ;;
vim-register-picker-panel-pick-pastes-selection)
    bin=$(make_fake_path)
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        "$script_under_test"

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    grep -Fqx $'a\tnamed\talpha register line 1 / alpha register line 2\ta' "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fqx $'b\tnamed\tbravo register\tb' "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fqx -- '--preview-label= register ' "${DOTFILES_TEST_TMP}/fzf-args"
    cmp -s <(printf 'alpha register line 1\nalpha register line 2\n') "${DOTFILES_TEST_TMP}/clipboard.txt"
    grep -Fxq 'key --clearmodifiers ctrl+shift+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    rg -q '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^xclip$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^paste-terminal$' "${DOTFILES_TEST_TMP}/events.log"
    panel_closed_line=$(rg -n '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    focus_still_picker_line=$(rg -n '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    xclip_line=$(rg -n '^xclip$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    paste_line=$(rg -n '^paste-terminal$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    [ "$panel_closed_line" -lt "$xclip_line" ]
    [ "$xclip_line" -lt "$focus_still_picker_line" ]
    [ "$focus_still_picker_line" -lt "$paste_line" ]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
