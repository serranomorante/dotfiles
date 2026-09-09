#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities color-mode shell
# dotfiles-test-case: agent-color-mode-syntax
# dotfiles-test-case: agent-color-mode-detects-kde-scheme
# dotfiles-test-case: agent-color-mode-writes-claude-theme
# dotfiles-test-case: agent-color-mode-skips-noop-write
# dotfiles-test-case: agent-color-mode-flips-codex-syntax-theme
# dotfiles-test-case: agent-color-mode-keeps-codex-tui-table
# dotfiles-test-case: agent-color-mode-rejects-unknown-mode

# Purpose: Verify the system color mode is pushed into the AI agent configs.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/agent-color-mode"
listener="${DOTFILES_TEST_ROOT}/utilities/bin/dbus_listen_color_change"
claude_theme="${HOME}/.claude/themes/dotfiles-system.json"
codex_config="${HOME}/.codex/config.toml"

write_kde_scheme() {
    mkdir -p "$XDG_CONFIG_HOME"
    printf 'Name=Breeze\nColorScheme=%s\n' "$1" >"${XDG_CONFIG_HOME}/kdeglobals"
}

write_codex_config() {
    mkdir -p "${HOME}/.codex"
    printf '%s' "$1" >"$codex_config"
}

case "${DOTFILES_TEST_CASE:-}" in
agent-color-mode-syntax)
    sh -n "$script_under_test"
    bash -n "$listener"
    ;;
agent-color-mode-detects-kde-scheme)
    mkdir -p "${HOME}/.claude"

    write_kde_scheme BreezeLight
    "$script_under_test"
    grep -Fq '"base": "light"' "$claude_theme"

    write_kde_scheme BreezeDark
    "$script_under_test"
    grep -Fq '"base": "dark"' "$claude_theme"

    # A missing scheme keeps the workstation default instead of guessing light.
    rm -f "${XDG_CONFIG_HOME}/kdeglobals"
    "$script_under_test" light
    "$script_under_test"
    grep -Fq '"base": "dark"' "$claude_theme"
    ;;
agent-color-mode-writes-claude-theme)
    # Without ~/.claude the agent is not installed for this user; do not create it.
    "$script_under_test" light
    refute test -e "$claude_theme"

    mkdir -p "${HOME}/.claude"
    "$script_under_test" light
    grep -Fq '"name": "Dotfiles System"' "$claude_theme"
    grep -Fq '"base": "light"' "$claude_theme"
    ;;
agent-color-mode-skips-noop-write)
    mkdir -p "${HOME}/.claude"
    "$script_under_test" light
    before=$(stat -c %i "$claude_theme")

    # Claude Code watches the themes directory, so an unchanged mode must not
    # replace the file and wake every running session.
    "$script_under_test" light
    [ "$(stat -c %i "$claude_theme")" = "$before" ]

    "$script_under_test" dark
    refute test "$(stat -c %i "$claude_theme")" = "$before"
    ;;
agent-color-mode-flips-codex-syntax-theme)
    write_codex_config $'model = "gpt-5"\n\n[permissions.p]\nextends = ":workspace"\n'

    "$script_under_test" light
    grep -Fqx 'tui.theme = "base16-ocean.light"' "$codex_config"

    "$script_under_test" dark
    grep -Fqx 'tui.theme = "base16-ocean.dark"' "$codex_config"

    # The managed block stays a single root-level key ahead of every table.
    [ "$(grep -c '^tui\.theme = ' "$codex_config")" = 1 ]
    [ "$(grep -n '^tui\.theme = ' "$codex_config" | cut -d: -f1)" -lt "$(grep -n '^\[permissions\.p\]' "$codex_config" | cut -d: -f1)" ]
    grep -Fqx 'model = "gpt-5"' "$codex_config"
    grep -Fqx 'extends = ":workspace"' "$codex_config"
    ;;
agent-color-mode-keeps-codex-tui-table)
    # A [tui] table would turn the managed dotted key into a duplicate and break
    # Codex config parsing, so the file has to be left untouched.
    original=$'model = "gpt-5"\n\n[tui]\ntheme = "dracula"\n'
    write_codex_config "$original"

    "$script_under_test" light 2>"${DOTFILES_TEST_TMP}/stderr"
    [ "$(cat "$codex_config")" = "$(printf '%s' "$original")" ]
    grep -Fq '[tui] table' "${DOTFILES_TEST_TMP}/stderr"
    ;;
agent-color-mode-rejects-unknown-mode)
    status=0
    "$script_under_test" purple 2>"${DOTFILES_TEST_TMP}/stderr" || status=$?
    [ "$status" = 2 ]
    grep -Fq 'unknown color mode: purple' "${DOTFILES_TEST_TMP}/stderr"
    ;;
*)
    echo "unknown test case: ${DOTFILES_TEST_CASE:-}" >&2
    exit 1
    ;;
esac
