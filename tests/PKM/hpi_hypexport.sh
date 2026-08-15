#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: pkm hypexport hypothesis kwallet shell fast
# dotfiles-test-case: hypexport-script-syntax
# dotfiles-test-case: hypexport-reads-credentials-from-kwallet
# dotfiles-test-case: hypexport-uses-env-overrides
# dotfiles-test-case: hypexport-aborts-without-credentials
# dotfiles-test-case: hypexport-treats-failed-read-entry-as-absent

# Purpose: Verify the hypexport export script reads its credentials from the
# KWallet keyring provisioned by setup-kwallet instead of the removed
# data/secrets gpg files.

script_under_test="${DOTFILES_TEST_ROOT}/PKM/bin/hpi-hypexport.sh"

fake_bin_path() {
    local bin="${DOTFILES_TEST_TMP}/home/bin"
    mkdir -p "$bin"
    printf '%s\n' "$bin"
}

write_fake_kwallet_query() {
    local bin=$1
    cat >"${bin}/kwallet-query" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

entry=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder) shift; folder=$1 ;;
        --read-password) shift; entry=$1 ;;
        *) wallet=$1 ;;
    esac
    shift
done

case "$entry" in
    hypothesis-username) printf 'kwallet-username\n' ;;
    hypothesis-password) printf 'kwallet-password\n' ;;
    *)
        printf 'Failed to read entry %s value from the %s wallet.\n' "$entry" "$wallet"
        exit 1
        ;;
esac
SH
    chmod +x "${bin}/kwallet-query"
}

write_empty_kwallet_query() {
    local bin=$1
    cat >"${bin}/kwallet-query" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "${bin}/kwallet-query"
}

write_fake_fj_py() {
    local bin=$1
    cat >"${bin}/fj-py" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/fj-py.args"

while [[ $# -gt 0 && "$1" != "--" ]]; do
    shift
done
shift || true
exec "$@"
SH
    chmod +x "${bin}/fj-py"
}

write_fake_python() {
    local python="${DOTFILES_TEST_TMP}/home/data/apps/PKM/.venv/bin/python"
    mkdir -p "$(dirname "$python")"
    cat >"$python" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/hypexport.args"
printf '%s\n' '{"profile": {"user": "kwallet-username"}, "annotations": [{"id": "abc123"}]}'
SH
    chmod +x "$python"
}

case "${DOTFILES_TEST_CASE:-}" in
hypexport-script-syntax)
    bash -n "$script_under_test"
    ;;
hypexport-reads-credentials-from-kwallet)
    bin=$(fake_bin_path)
    write_fake_kwallet_query "$bin"
    write_fake_fj_py "$bin"
    write_fake_python

    PATH="$bin:/usr/bin:/bin" "$script_under_test" >"${DOTFILES_TEST_TMP}/export.out"

    rg -q 'Export completed successfully' "${DOTFILES_TEST_TMP}/export.out"
    rg -q -- '--username kwallet-username --token kwallet-password' "${DOTFILES_TEST_TMP}/hypexport.args"
    ls "${DOTFILES_TEST_TMP}/home/data/PKM/data/highlights"/hypothesis.*.json >/dev/null
    ;;
hypexport-uses-env-overrides)
    bin=$(fake_bin_path)
    write_fake_kwallet_query "$bin"
    write_fake_fj_py "$bin"
    write_fake_python

    HYPOTHESIS_USERNAME=env-username HYPOTHESIS_TOKEN=env-token PATH="$bin:/usr/bin:/bin" "$script_under_test" >"${DOTFILES_TEST_TMP}/export.out"

    rg -q 'Export completed successfully' "${DOTFILES_TEST_TMP}/export.out"
    rg -q -- '--username env-username --token env-token' "${DOTFILES_TEST_TMP}/hypexport.args"
    refute rg -q 'kwallet-username' "${DOTFILES_TEST_TMP}/hypexport.args"
    ;;
hypexport-aborts-without-credentials)
    bin=$(fake_bin_path)
    write_empty_kwallet_query "$bin"

    if PATH="$bin:/usr/bin:/bin" "$script_under_test" >"${DOTFILES_TEST_TMP}/export.out" 2>&1; then
        printf 'missing credentials should abort the export\n' >&2
        exit 1
    fi
    rg -q 'Username or token is missing' "${DOTFILES_TEST_TMP}/export.out"
    if compgen -G "${DOTFILES_TEST_TMP}/home/data/PKM/data/highlights/hypothesis.*.json" >/dev/null; then
        printf 'no highlights file should be written without credentials\n' >&2
        exit 1
    fi
    ;;
hypexport-treats-failed-read-entry-as-absent)
    bin=$(fake_bin_path)
    cat >"${bin}/kwallet-query" <<'SH'
#!/usr/bin/env bash
printf 'Failed to read entry hypothesis-username value from the kdewallet wallet.\n'
printf 'Failed to read entry hypothesis-password value from the kdewallet wallet.\n'
exit 1
SH
    chmod +x "${bin}/kwallet-query"

    if PATH="$bin:/usr/bin:/bin" "$script_under_test" >"${DOTFILES_TEST_TMP}/export.out" 2>&1; then
        printf 'unreadable KWallet entries should abort the export\n' >&2
        exit 1
    fi
    rg -q 'Username or token is missing' "${DOTFILES_TEST_TMP}/export.out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
