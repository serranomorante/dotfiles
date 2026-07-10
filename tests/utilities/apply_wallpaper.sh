#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities wallpaper shell
# dotfiles-test-case: apply-wallpaper-syntax
# dotfiles-test-case: apply-wallpaper-applies-image
# dotfiles-test-case: apply-wallpaper-missing-directory-is-noop
# dotfiles-test-case: apply-wallpaper-without-x-is-noop

# Purpose: Verify the safe feh wrapper used by setup-displays and feh.service.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/apply-wallpaper"

make_fake_path() {
    local bin=$1

    mkdir -p "$bin"
    ln -s /usr/bin/bash "${bin}/bash"
    ln -s /usr/bin/find "${bin}/find"
    ln -s /usr/bin/grep "${bin}/grep"
    cat >"${bin}/shuf" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r line; do
    printf '%s\n' "$line"
    exit 0
done
BASH
    chmod +x "${bin}/shuf"
}

write_fake_feh() {
    local bin=$1

    cat >"${bin}/feh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/feh.log"
BASH
    chmod +x "${bin}/feh"
}

write_fake_xrandr() {
    local bin=$1
    local available=${2:-yes}

    cat >"${bin}/xrandr" <<BASH
#!/usr/bin/env bash
set -euo pipefail

case "\$*" in
--query)
    if [[ "${available}" == "yes" ]]; then
        printf '%s\n' 'eDP-1 connected primary 1920x1080+0+0'
        exit 0
    fi
    exit 1
    ;;
*)
    printf 'unexpected xrandr call: %s\n' "\$*" >&2
    exit 2
    ;;
esac
BASH
    chmod +x "${bin}/xrandr"
}

run_apply_wallpaper() {
    local x_available=${1:-yes}
    local bin="${DOTFILES_TEST_TMP}/bin"
    local home="${DOTFILES_TEST_TMP}/home"

    make_fake_path "$bin"
    write_fake_feh "$bin"
    write_fake_xrandr "$bin" "$x_available"
    mkdir -p "$home"
    DISPLAY=:99 PATH="$bin" HOME="$home" "$script_under_test" >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"
}

case "${DOTFILES_TEST_CASE:-}" in
apply-wallpaper-syntax)
    sh -n "$script_under_test"
    ;;
apply-wallpaper-applies-image)
    mkdir -p "${DOTFILES_TEST_TMP}/home/.wallpapers"
    printf 'image\n' >"${DOTFILES_TEST_TMP}/home/.wallpapers/space image.jpg"
    printf 'ignored\n' >"${DOTFILES_TEST_TMP}/home/.wallpapers/not-image.txt"
    run_apply_wallpaper yes
    expected="--bg-fill ${DOTFILES_TEST_TMP}/home/.wallpapers/space image.jpg"
    actual=$(cat "${DOTFILES_TEST_TMP}/feh.log")
    [[ "$actual" == "$expected" ]]
    ;;
apply-wallpaper-missing-directory-is-noop)
    run_apply_wallpaper yes
    [[ ! -e "${DOTFILES_TEST_TMP}/feh.log" ]]
    grep -q "wallpaper directory does not exist" "${DOTFILES_TEST_TMP}/stderr"
    ;;
apply-wallpaper-without-x-is-noop)
    mkdir -p "${DOTFILES_TEST_TMP}/home/.wallpapers"
    printf 'image\n' >"${DOTFILES_TEST_TMP}/home/.wallpapers/space.jpg"
    run_apply_wallpaper no
    [[ ! -e "${DOTFILES_TEST_TMP}/feh.log" ]]
    grep -q "no X server is available" "${DOTFILES_TEST_TMP}/stderr"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
