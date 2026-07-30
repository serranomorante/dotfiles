#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: opencode shell fast
# dotfiles-test-firejail: disabled
# dotfiles-test-case: opencode-mini-readable-rewrites-dark-foregrounds

# Purpose: Guard the PTY relay that makes opencode --mini menu selections readable in tmux/Neovim.

wrapper="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/files/opencode-mini-readable"

case "${DOTFILES_TEST_CASE:-}" in
opencode-mini-readable-rewrites-dark-foregrounds)
    fake_target="${DOTFILES_TEST_TMP}/fake-opencode"
    output="${DOTFILES_TEST_TMP}/output.ansi"
    cat >"$fake_target" <<'SCRIPT'
#!/usr/bin/env bash
printf '\033[38;2;15;23;42mOpen editor\033[0m\n'
printf '\033[38;2;0;0;0mblack text\033[0m\n'
SCRIPT
    chmod +x "$fake_target"

    OPENCODE_MINI_READABLE_TARGET="$fake_target" "$wrapper" >"$output"

    grep -F $'\033[38;2;240;246;252mOpen editor' "$output" >/dev/null
    grep -F $'\033[38;2;125;133;144mblack text' "$output" >/dev/null
    if grep -F $'\033[38;2;15;23;42m' "$output" >/dev/null; then
        printf 'dark focused foreground was not rewritten\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
