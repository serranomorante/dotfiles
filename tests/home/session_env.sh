#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: home
# dotfiles-test-tags: home shell systemd environment path
# dotfiles-test-case: session-env-syntax
# dotfiles-test-case: session-env-builds-stable-path
# dotfiles-test-case: bashrc-noninteractive-loads-only-shared-env
# dotfiles-test-case: bashrc-interactive-loads-shell-features
# dotfiles-test-case: systemd-generator-prints-shared-env
# dotfiles-test-case: dotfiles-env-print-uses-shared-env

# Purpose: Verify the shared session environment is the single PATH source for
# Bash and systemd user services.

session_env="${DOTFILES_TEST_ROOT}/home/lib/session-env.bash"
bashrc="${DOTFILES_TEST_ROOT}/home/dot-bashrc"
generator="${DOTFILES_TEST_ROOT}/utilities/dot-config/systemd/user-environment-generators/30-dotfiles-session-env"
dotfiles_env="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-env"

make_home() {
    local home="${DOTFILES_TEST_TMP}/home"

    mkdir -p "$home"
    ln -s "$DOTFILES_TEST_ROOT" "${home}/dotfiles"
    ln -s "${DOTFILES_TEST_ROOT}/home/dot-bashrc" "${home}/.bashrc"
    printf '%s\n' "$home"
}

assert_contains() {
    local haystack=$1
    local needle=$2

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'expected to find %s in:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

assert_not_contains() {
    local haystack=$1
    local needle=$2

    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'expected not to find %s in:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

shared_env_output() {
    local home=$1
    local inherited_path=${2:-/tmp/leaked-path:/usr/bin:/bin}

    env -i \
        HOME="$home" \
        XDG_RUNTIME_DIR=/run/user/4242 \
        PATH="$inherited_path" \
        bash -c 'source "$HOME/dotfiles/home/lib/session-env.bash"; env'
}

extract_env_value() {
    local key=$1

    sed -n "s/^${key}=//p" | sed -n '1p'
}

case "${DOTFILES_TEST_CASE:-}" in
session-env-syntax)
    bash -n "$session_env" "$bashrc" "$generator" "$dotfiles_env"
    ;;
session-env-builds-stable-path)
    home=$(make_home)
    output=$(shared_env_output "$home")
    path=$(printf '%s\n' "$output" | extract_env_value PATH)

    assert_contains "$path" "${home}/bin"
    assert_contains "$path" "${home}/.local/bin"
    assert_contains "$path" "${home}/.local/kitty.app/bin"
    assert_contains "$path" "${home}/.volta/tools/image/node/22.23.1/bin"
    assert_contains "$path" "${home}/.pyenv/shims"
    assert_contains "$path" "${home}/go/bin"
    assert_not_contains "$path" /tmp/leaked-path
    [[ "$path" == "${home}/bin:"* ]]
    [[ "$(printf '%s' "$path" | tr ':' '\n' | grep -Fx "${home}/bin" | wc -l)" -eq 1 ]]
    ;;
bashrc-noninteractive-loads-only-shared-env)
    home=$(make_home)
    output=$(
        env -i HOME="$home" XDG_RUNTIME_DIR=/run/user/4242 PATH=/tmp/leaked-path:/usr/bin:/bin \
            bash -c 'source "$HOME/.bashrc"; printf "PATH=%s\n" "$PATH"; alias agent-tasks 2>/dev/null || true; type nvim 2>/dev/null || true'
    )
    path=$(printf '%s\n' "$output" | extract_env_value PATH)

    assert_contains "$path" "${home}/bin"
    assert_contains "$path" "${home}/.volta/bin"
    assert_not_contains "$path" /tmp/leaked-path
    assert_not_contains "$output" "alias agent-tasks="
    assert_not_contains "$output" "nvim is a function"
    ;;
bashrc-interactive-loads-shell-features)
    home=$(make_home)
    output=$(
        env -i HOME="$home" XDG_RUNTIME_DIR=/run/user/4242 PATH=/usr/bin:/bin \
            bash -ic 'printf "PATH=%s\n" "$PATH"; alias agent-tasks; type nvim' 2>/dev/null
    )

    assert_contains "$output" "alias agent-tasks="
    assert_contains "$output" "nvim is a function"
    assert_contains "$output" "${home}/bin"
    ;;
systemd-generator-prints-shared-env)
    home=$(make_home)
    output=$(
        env -i \
            HOME="$home" \
            XDG_RUNTIME_DIR=/run/user/4242 \
            PATH=/tmp/leaked-path:/usr/bin:/bin \
            DOTFILES_SESSION_ENV_FILE="${home}/dotfiles/home/lib/session-env.bash" \
            "$generator"
    )
    path=$(printf '%s\n' "$output" | extract_env_value PATH)

    assert_contains "$output" "VOLTA_HOME=${home}/.volta"
    assert_contains "$output" "PYENV_ROOT=${home}/.pyenv"
    assert_contains "$output" "SSH_AUTH_SOCK=/run/user/4242/ssh-agent.socket"
    assert_contains "$path" "${home}/bin"
    assert_not_contains "$path" /tmp/leaked-path
    ;;
dotfiles-env-print-uses-shared-env)
    home=$(make_home)
    output=$(
        env -i \
            HOME="$home" \
            XDG_RUNTIME_DIR=/run/user/4242 \
            PATH=/tmp/leaked-path:/usr/bin:/bin \
            DOTFILES_SESSION_ENV_FILE="${home}/dotfiles/home/lib/session-env.bash" \
            "$dotfiles_env" print
    )
    path=$(printf '%s\n' "$output" | extract_env_value PATH)

    assert_contains "$output" "VOLTA_HOME=${home}/.volta"
    assert_contains "$path" "${home}/bin"
    assert_contains "$path" "${home}/.local/share/yabridge"
    assert_not_contains "$path" /tmp/leaked-path
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
