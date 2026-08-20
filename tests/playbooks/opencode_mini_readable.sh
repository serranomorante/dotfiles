#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: opencode shell fast
# dotfiles-test-firejail: disabled
# dotfiles-test-case: opencode-mini-readable-rewrites-dark-foregrounds
# dotfiles-test-case: opencode-mini-readable-flushes-cursor-tail-while-alive

# Purpose: Guard the PTY relay that makes opencode --mini menu selections readable in tmux/Neovim.

# Note: the relay must also flush its lookahead tail while the target stays
# alive, otherwise opencode's final cursor-show (ESC [ ? 2 5 h) is held back
# until exit and the terminal cursor never appears. See
# opencode-mini-readable-flushes-cursor-tail-while-alive below.

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
opencode-mini-readable-flushes-cursor-tail-while-alive)
    fake_target="${DOTFILES_TEST_TMP}/fake-opencode-tail"
    output="${DOTFILES_TEST_TMP}/tail.ansi"
    cat >"$fake_target" <<'SCRIPT'
#!/usr/bin/env bash
printf 'some payload text long enough that the cursor sequence is the tail\n\033[?25h'
sleep 30
SCRIPT
    chmod +x "$fake_target"

    OPENCODE_MINI_READABLE_TARGET="$fake_target" timeout 2 "$wrapper" >"$output" &
    wrapper_pid=$!
    sleep 0.7
    if ! grep -F $'\033[?25h' "$output" >/dev/null; then
        printf 'trailing cursor-show was not flushed while target stayed alive\n' >&2
        kill "$wrapper_pid" 2>/dev/null || true
        exit 1
    fi
    wait "$wrapper_pid" 2>/dev/null || true
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
