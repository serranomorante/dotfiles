#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: firejail profile-checker shell fast
# dotfiles-test-firejail: disabled
# dotfiles-test-case: fj-profile-checker-syntax
# dotfiles-test-case: fj-profile-checker-execs-command-when-profile-satisfied
# dotfiles-test-case: fj-profile-checker-resolves-profile-name-from-home-config
# dotfiles-test-case: fj-profile-checker-resolves-relative-profile-from-cwd
# dotfiles-test-case: fj-profile-checker-recurses-relative-includes
# dotfiles-test-case: fj-profile-checker-resolves-includes-from-home-config
# dotfiles-test-case: fj-profile-checker-resolves-absolute-includes
# dotfiles-test-case: fj-profile-checker-handles-include-cycles
# dotfiles-test-case: fj-profile-checker-expands-home-path-forms
# dotfiles-test-case: fj-profile-checker-strips-comments-and-whitespace
# dotfiles-test-case: fj-profile-checker-reads-profile-from-readonly-home-config
# dotfiles-test-case: fj-profile-checker-preserves-command-arguments
# dotfiles-test-case: fj-profile-checker-accepts-real-blacklist-placeholder
# dotfiles-test-case: fj-profile-checker-ignores-noblacklist-lines
# dotfiles-test-case: fj-profile-checker-fails-on-missing-whitelist
# dotfiles-test-case: fj-profile-checker-fails-on-writable-whitelist-ro
# dotfiles-test-case: fj-profile-checker-fails-on-visible-blacklist
# dotfiles-test-case: fj-profile-checker-fails-on-unreadable-profile
# dotfiles-test-case: fj-profile-checker-fails-on-unresolved-include
# dotfiles-test-case: fj-profile-checker-rejects-missing-separator

# Purpose: Fast real-Firejail tests for fj-profile-checker profile parsing and fail-closed behavior.

checker="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/files/fj-profile-checker"
path_value=${PATH:-/usr/local/bin:/usr/bin:/bin}

require_firejail() {
    command -v firejail >/dev/null 2>&1 || {
        printf 'firejail is required for fj-profile-checker integration tests\n' >&2
        exit 77
    }
}

make_fixture() {
    require_firejail

    fixture="${DOTFILES_TEST_TMP}/fixture"
    home="${fixture}/home"
    profile_dir="${home}/.config/firejail"
    visible="${fixture}/visible"
    readonly="${fixture}/readonly"
    hidden="${fixture}/hidden"
    command_marker="${fixture}/command-ran"
    output="${fixture}/checker.out"
    sandbox_profile="${profile_dir}/sandbox.profile"

    mkdir -p "$profile_dir" "$visible" "$readonly" "$home/from-home" "$home/from-tilde" "$home/readonly-home"

    cat >"$sandbox_profile" <<PROFILE
quiet
whitelist ${fixture}
whitelist-ro ${readonly}
whitelist-ro ${home}/readonly-home
PROFILE
}

write_command() {
    command_file="${fixture}/write-marker.sh"
    cat >"$command_file" <<'SH'
#!/usr/bin/env sh
printf 'ran:%s\n' "$1" >"$2"
SH
    chmod +x "$command_file"
}

write_satisfied_profile() {
    profile=$1
    cat >"$profile" <<PROFILE
quiet
whitelist ${fixture}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE
}

run_in_firejail() {
    firejail_profile=$1
    shift

    (
        cd "$fixture"
        HOME="$home" firejail --quiet --profile="$firejail_profile" -- \
            env -i \
            HOME="$home" \
            PATH="$path_value" \
            LANG=C.UTF-8 \
            TERM=dumb \
            "$@"
    )
}

run_checker() {
    firejail_profile=$1
    expected_profile=$2
    shift 2

    run_in_firejail "$firejail_profile" "$checker" "$expected_profile" "$@"
}

assert_marker() {
    expected=$1
    [ -f "$command_marker" ] || {
        printf 'expected command marker to exist\n' >&2
        exit 1
    }
    grep -Fxq "$expected" "$command_marker"
}

assert_no_marker() {
    [ ! -e "$command_marker" ] || {
        printf 'command unexpectedly ran\n' >&2
        exit 1
    }
}

assert_fails_without_exec() {
    expected_message=$1
    firejail_profile=$2
    expected_profile=$3
    shift 3

    if run_checker "$firejail_profile" "$expected_profile" "$@" >"$output" 2>&1; then
        printf 'checker unexpectedly succeeded\n' >&2
        exit 1
    fi

    assert_no_marker
    grep -Fq "$expected_message" "$output"
}

case "${DOTFILES_TEST_CASE:-}" in
fj-profile-checker-syntax)
    sh -n "$checker"
    ;;
fj-profile-checker-execs-command-when-profile-satisfied)
    make_fixture
    write_command
    write_satisfied_profile "${fixture}/main.profile"

    run_checker "${fixture}/main.profile" "${fixture}/main.profile" -- "$command_file" ok "$command_marker"
    assert_marker "ran:ok"
    ;;
fj-profile-checker-resolves-profile-name-from-home-config)
    make_fixture
    write_command
    write_satisfied_profile "${profile_dir}/named.profile"

    run_checker "${profile_dir}/named.profile" named.profile -- "$command_file" named "$command_marker"
    assert_marker "ran:named"
    ;;
fj-profile-checker-resolves-relative-profile-from-cwd)
    make_fixture
    write_command
    mkdir -p "${fixture}/profiles"
    write_satisfied_profile "${fixture}/profiles/relative.profile"

    run_checker "${fixture}/profiles/relative.profile" profiles/relative.profile -- "$command_file" relative "$command_marker"
    assert_marker "ran:relative"
    ;;
fj-profile-checker-recurses-relative-includes)
    make_fixture
    write_command
    mkdir -p "${fixture}/profiles/subdir"
    cat >"${fixture}/profiles/main.profile" <<'PROFILE'
quiet
include subdir/child.profile
PROFILE
    cat >"${fixture}/profiles/subdir/child.profile" <<PROFILE
include sibling.inc
whitelist ${fixture}
PROFILE
    cat >"${fixture}/profiles/subdir/sibling.inc" <<PROFILE
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "$sandbox_profile" "${fixture}/profiles/main.profile" -- "$command_file" included "$command_marker"
    assert_marker "ran:included"
    ;;
fj-profile-checker-resolves-includes-from-home-config)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<'PROFILE'
include shared.inc
PROFILE
    cat >"${profile_dir}/shared.inc" <<PROFILE
whitelist ${visible}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" home-include "$command_marker"
    assert_marker "ran:home-include"
    ;;
fj-profile-checker-resolves-absolute-includes)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<PROFILE
include ${fixture}/absolute.inc
whitelist ${visible}
PROFILE
    cat >"${fixture}/absolute.inc" <<PROFILE
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" absolute-include "$command_marker"
    assert_marker "ran:absolute-include"
    ;;
fj-profile-checker-handles-include-cycles)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<PROFILE
include child.profile
whitelist ${visible}
PROFILE
    cat >"${fixture}/child.profile" <<PROFILE
include main.profile
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" cycle "$command_marker"
    assert_marker "ran:cycle"
    ;;
fj-profile-checker-expands-home-path-forms)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<'PROFILE'
quiet
whitelist ${HOME}/from-home
whitelist ~/from-tilde
whitelist-ro ${HOME}/readonly-home
blacklist ${HOME}/does-not-exist
PROFILE

    run_checker "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" expanded "$command_marker"
    assert_marker "ran:expanded"
    ;;
fj-profile-checker-strips-comments-and-whitespace)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<PROFILE
        quiet
        whitelist ${fixture}        # visible fixture
        whitelist-ro ${readonly}    # readonly fixture
        blacklist ${hidden}         # absent fixture
PROFILE

    run_checker "${fixture}/main.profile" "${fixture}/main.profile" -- "$command_file" comments "$command_marker"
    assert_marker "ran:comments"
    ;;
fj-profile-checker-reads-profile-from-readonly-home-config)
    make_fixture
    write_command
    cat >"${profile_dir}/readonly-home.profile" <<PROFILE
whitelist ${fixture}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "$sandbox_profile" readonly-home.profile -- "$command_file" readonly-home "$command_marker"
    assert_marker "ran:readonly-home"
    ;;
fj-profile-checker-preserves-command-arguments)
    make_fixture
    command_file="${fixture}/write-args.sh"
    cat >"$command_file" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$@" >"$1"
SH
    chmod +x "$command_file"
    write_satisfied_profile "${fixture}/main.profile"

    run_checker "${fixture}/main.profile" "${fixture}/main.profile" -- "$command_file" "$command_marker" "arg with spaces" "--flag" "literal-*"
    grep -Fxq "$command_marker" "$command_marker"
    grep -Fxq "arg with spaces" "$command_marker"
    grep -Fxq -- "--flag" "$command_marker"
    grep -Fxq "literal-*" "$command_marker"
    ;;
fj-profile-checker-accepts-real-blacklist-placeholder)
    make_fixture
    write_command
    mkdir -p "$hidden"
    write_satisfied_profile "${fixture}/main.profile"

    run_checker "${fixture}/main.profile" "${fixture}/main.profile" -- "$command_file" blacklisted "$command_marker"
    assert_marker "ran:blacklisted"
    ;;
fj-profile-checker-ignores-noblacklist-lines)
    make_fixture
    write_command
    mkdir -p "$visible"
    cat >"${fixture}/main.profile" <<PROFILE
noblacklist ${visible}
whitelist ${fixture}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE

    run_checker "${fixture}/main.profile" "${fixture}/main.profile" -- "$command_file" noblacklist "$command_marker"
    assert_marker "ran:noblacklist"
    ;;
fj-profile-checker-fails-on-missing-whitelist)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<PROFILE
whitelist ${fixture}/missing
PROFILE

    assert_fails_without_exec "sandbox does not expose required path" "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" fail "$command_marker"
    ;;
fj-profile-checker-fails-on-writable-whitelist-ro)
    make_fixture
    write_command
    writable_sandbox_profile="${profile_dir}/sandbox-writable.profile"
    cat >"$writable_sandbox_profile" <<PROFILE
quiet
whitelist ${fixture}
PROFILE
    cat >"${fixture}/main.profile" <<PROFILE
whitelist-ro ${visible}
PROFILE

    assert_fails_without_exec "sandbox exposes read-only path as writable" "$writable_sandbox_profile" "${fixture}/main.profile" -- "$command_file" fail "$command_marker"
    ;;
fj-profile-checker-fails-on-visible-blacklist)
    make_fixture
    write_command
    mkdir -p "$hidden"
    cat >"${fixture}/main.profile" <<PROFILE
blacklist ${hidden}
PROFILE

    assert_fails_without_exec "sandbox exposes blocked path" "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" fail "$command_marker"
    ;;
fj-profile-checker-fails-on-unreadable-profile)
    make_fixture
    write_command
    unreadable_profile="${fixture}/unreadable.profile"
    cat >"$unreadable_profile" <<PROFILE
whitelist ${fixture}
PROFILE
    chmod 000 "$unreadable_profile"

    assert_fails_without_exec "cannot read Firejail profile" "$sandbox_profile" "$unreadable_profile" -- "$command_file" fail "$command_marker"
    ;;
fj-profile-checker-fails-on-unresolved-include)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<'PROFILE'
include missing.inc
PROFILE

    assert_fails_without_exec "cannot resolve included Firejail profile" "$sandbox_profile" "${fixture}/main.profile" -- "$command_file" fail "$command_marker"
    ;;
fj-profile-checker-rejects-missing-separator)
    make_fixture
    write_command
    cat >"${fixture}/main.profile" <<PROFILE
whitelist ${visible}
PROFILE

    assert_fails_without_exec "expected command separator --" "$sandbox_profile" "${fixture}/main.profile" "$command_file" fail "$command_marker"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
