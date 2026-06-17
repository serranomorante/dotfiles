#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: github token kwallet git shell fast
# dotfiles-test-case: github-token-helpers-syntax
# dotfiles-test-case: github-token-uses-env-token
# dotfiles-test-case: github-token-empty-kwallet-is-absent
# dotfiles-test-case: github-askpass-returns-username-and-token
# dotfiles-test-case: github-git-falls-back-without-token
# dotfiles-test-case: github-git-enables-askpass-with-token

token_helper="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-github-token"
askpass_helper="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-github-askpass"
git_helper="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-github-git"

fake_bin_path() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    printf '%s\n' "$bin"
}

write_fake_git() {
    local bin=$1
    cat >"${bin}/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/git.args"
printf '%s\n' "${GIT_ASKPASS:-}" >"${DOTFILES_TEST_TMP}/git.askpass"
printf '%s\n' "${GIT_TERMINAL_PROMPT:-}" >"${DOTFILES_TEST_TMP}/git.terminal_prompt"
SH
    chmod +x "${bin}/git"
}

write_fake_kwallet_query() {
    local bin=$1
    local output=$2
    cat >"${bin}/kwallet-query" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' '$output'
SH
    chmod +x "${bin}/kwallet-query"
}

case "${DOTFILES_TEST_CASE:-}" in
github-token-helpers-syntax)
    bash -n "$token_helper"
    bash -n "$askpass_helper"
    bash -n "$git_helper"
    ;;
github-token-uses-env-token)
    DOTFILES_GITHUB_TOKEN=from-env PATH=/usr/bin:/bin "$token_helper" >"${DOTFILES_TEST_TMP}/token.out"
    [[ "$(cat "${DOTFILES_TEST_TMP}/token.out")" == "from-env" ]]
    ;;
github-token-empty-kwallet-is-absent)
    bin=$(fake_bin_path)
    write_fake_kwallet_query "$bin" ""
    if PATH="$bin:/usr/bin:/bin" "$token_helper" >"${DOTFILES_TEST_TMP}/token.out"; then
        printf 'empty kwallet token should be treated as absent\n' >&2
        exit 1
    fi
    [ ! -s "${DOTFILES_TEST_TMP}/token.out" ]
    ;;
github-askpass-returns-username-and-token)
    DOTFILES_GITHUB_TOKEN=from-env "$askpass_helper" "Username for https://github.com" >"${DOTFILES_TEST_TMP}/username.out"
    DOTFILES_GITHUB_TOKEN=from-env "$askpass_helper" "Password for https://x-access-token@github.com" >"${DOTFILES_TEST_TMP}/password.out"
    [[ "$(cat "${DOTFILES_TEST_TMP}/username.out")" == "x-access-token" ]]
    [[ "$(cat "${DOTFILES_TEST_TMP}/password.out")" == "from-env" ]]
    ;;
github-git-falls-back-without-token)
    bin=$(fake_bin_path)
    write_fake_git "$bin"
    env -u DOTFILES_GITHUB_TOKEN -u RENOVATE_GITHUB_COM_TOKEN -u GITHUB_COM_TOKEN -u GITHUB_TOKEN -u GH_TOKEN DOTFILES_GITHUB_TOKEN_DISABLED=1 PATH="$bin:/usr/bin:/bin" "$git_helper" clone https://github.com/example/repo.git "${DOTFILES_TEST_TMP}/repo"
    rg -q '^clone https://github\.com/example/repo\.git ' "${DOTFILES_TEST_TMP}/git.args"
    [ "$(cat "${DOTFILES_TEST_TMP}/git.askpass")" = "" ]
    [ "$(cat "${DOTFILES_TEST_TMP}/git.terminal_prompt")" = "" ]
    ;;
github-git-enables-askpass-with-token)
    bin=$(fake_bin_path)
    write_fake_git "$bin"
    DOTFILES_GITHUB_TOKEN=from-env PATH="$bin:/usr/bin:/bin" "$git_helper" clone https://github.com/example/repo.git "${DOTFILES_TEST_TMP}/repo"
    rg -q 'url\.https://x-access-token@github\.com/\.insteadOf=https://github\.com/' "${DOTFILES_TEST_TMP}/git.args"
    rg -q 'dotfiles-github-askpass$' "${DOTFILES_TEST_TMP}/git.askpass"
    [[ "$(cat "${DOTFILES_TEST_TMP}/git.terminal_prompt")" == "0" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
