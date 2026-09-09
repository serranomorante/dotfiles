#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: term
# dotfiles-test-tags: term kitty nvim shell python
# dotfiles-test-case: kitty-nvim-ref-syntax
# dotfiles-test-case: kitty-nvim-ref-marks-file-and-commit-references
# dotfiles-test-case: kitty-nvim-ref-marks-wrapped-references
# dotfiles-test-case: kitty-nvim-ref-file-opens-at-line
# dotfiles-test-case: kitty-nvim-ref-walks-up-to-project-session
# dotfiles-test-case: kitty-nvim-ref-commit-opens-diffview
# dotfiles-test-case: kitty-nvim-ref-commit-requires-matching-repository
# dotfiles-test-case: kitty-nvim-ref-missing-session-notifies
# dotfiles-test-case: kitty-nvim-ref-all-digit-hash-stays-a-commit

# Purpose: Verify agent evidence references are marked by the hints processor and
#   routed to the Neovim server that owns the cited path.

script_under_test="${DOTFILES_TEST_ROOT}/term/bin/kitty-open-nvim-ref"
hints_processor="${DOTFILES_TEST_ROOT}/term/dot-config/kitty/nvim-ref-hints.py"

make_fake_home() {
    local home="${DOTFILES_TEST_TMP}/home"

    mkdir -p "$home"
    ln -sfn "$DOTFILES_TEST_ROOT" "${home}/dotfiles"
    printf '%s\n' "$home"
}

make_fake_bin() {
    local bin="${DOTFILES_TEST_TMP}/bin"

    mkdir -p "$bin"
    cat >"${bin}/open_in_nvim" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/open_in_nvim.args"
SH
    cat >"${bin}/notify-send" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$*" >>"${DOTFILES_TEST_TMP}/notify-send.args"
SH
    chmod +x "${bin}/open_in_nvim" "${bin}/notify-send"
    printf '%s\n' "$bin"
}

nvim_socket_for_cwd() {
    (
        # shellcheck source=/dev/null
        source "${DOTFILES_TEST_ROOT}/term/bin/kitty-window-utils.sh"
        kitty_nvim_servername_from_cwd "$1"
    )
}

make_live_socket() {
    local socket
    socket=$(nvim_socket_for_cwd "$1")

    mkdir -p "$(dirname "$socket")"
    python3 - "$socket" <<'PY'
import socket
import sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
PY
    printf '%s\n' "$socket"
}

make_git_repo() {
    local repo=$1

    mkdir -p "$repo"
    git -C "$repo" -c init.defaultBranch=main init --quiet
    printf '%s\n' "$repo"
}

run_ref() {
    local home=$1 bin=$2 ref=$3

    HOME="$home" \
        DOTFILES_TEST_TMP="$DOTFILES_TEST_TMP" \
        PATH="${bin}:/usr/bin:/bin" \
        "$script_under_test" "$ref"
}

assert_file_contains() {
    local file=$1 expected=$2

    if ! grep -Fqx -- "$expected" "$file"; then
        printf 'expected line %q in %s:\n' "$expected" "$file" >&2
        cat "$file" >&2
        exit 1
    fi
}

# The socket paths the helper derives must match the ones the script resolves,
# so both sides run against the same runtime root.
export XDG_RUNTIME_DIR="${DOTFILES_TEST_TMP}/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

case "${DOTFILES_TEST_CASE:-}" in
kitty-nvim-ref-syntax)
    sh -n "$script_under_test"
    python3 -c "import ast, sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$hints_processor"
    ;;
kitty-nvim-ref-marks-file-and-commit-references)
    python3 - "$hints_processor" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("dotfiles_nvim_ref_hints", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def collect(text):
    def Mark(index, start, end, mark_text, groupdict):
        return mark_text

    return list(module.mark(text, None, Mark, None))


text = (
    "the guard is at nvim.file:/home/user/project/api/users.php:214.\n"
    "it landed in `nvim.commit:/home/user/project:4f4a77b`, see it.\n"
    "(nvim.commit:/home/user/project:1234567) needs no directory to disambiguate\n"
    "xnvim.file:/skipped/prefix:12 nvim.file:relative/path:9 nvim:/home/user/p:12\n"
    "nvim.file:/bad/locator:zzz nvim.commit:/too/short:4f4\n"
)

marks = collect(text)
assert marks == [
    "nvim.file:/home/user/project/api/users.php:214",
    "nvim.commit:/home/user/project:4f4a77b",
    "nvim.commit:/home/user/project:1234567",
], marks
PY
    ;;
kitty-nvim-ref-marks-wrapped-references)
    python3 - "$hints_processor" <<'PY_MARKS'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("dotfiles_nvim_ref_hints", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def collect(text):
    marks = []

    def Mark(index, start, end, mark_text, groupdict):
        marks.append((mark_text, text[start:end]))

    list(module.mark(text, None, Mark, None))
    return marks


# An agent's renderer hard-wraps its own output, so the break lands wherever the
# width falls: after a path separator, right after the leading slash, in the
# middle of a path segment, inside the line number, or just before a reference
# that starts a continuation line. A TUI also pads its lines to the render
# width, so the break carries whitespace on both sides.
text = (
    "  siembra bank-data-change en nvim.file:/home/user/project/appengine/api-dev/  \n"
    "  cloud-solutions/hrms/admin.php:1429 y data-error-report en nvim.file:/home/user/project/bucket\n"
    "  s/hrms/admin.php:14\n"
    "  43. está también en nvim.file:/ \n"
    "  home/user/project/keyd.conf:36. el cambio entró en \n"
    "  nvim.commit:/home/user/project:4f4a77b, y ahí está.\n"
)

marks = collect(text)
payloads = [payload for payload, _ in marks]
assert payloads == [
    "nvim.file:/home/user/project/appengine/api-dev/cloud-solutions/hrms/admin.php:1429",
    "nvim.file:/home/user/project/bucket" "s/hrms/admin.php:1443",
    "nvim.file:/home/user/project/keyd.conf:36",
    "nvim.commit:/home/user/project:4f4a77b",
], payloads

# The payload is reassembled whole, but the visible mark never spans a line break.
for payload, marked in marks:
    assert "\n" not in marked, (payload, marked)
    assert marked and payload.startswith(marked), (payload, marked)

# A complete reference at a line end is not extended by the next line's prose.
tail = collect("  el fallo está en nvim.file:/home/user/a.php:12  \n  the next paragraph\n")
assert [payload for payload, _ in tail] == ["nvim.file:/home/user/a.php:12"], tail
PY_MARKS
    ;;
kitty-nvim-ref-file-opens-at-line)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "$project"
    printf 'line\n' >"${project}/file.php"
    socket=$(make_live_socket "$project")

    run_ref "$home" "$bin" "nvim.file:${project}/file.php:214"

    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "--servername"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "$socket"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "kitty_simple_edit_at_line"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "${project}/file.php"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "214"
    ;;
kitty-nvim-ref-walks-up-to-project-session)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "${project}/src/deep"
    printf 'line\n' >"${project}/src/deep/file.php"
    socket=$(make_live_socket "$project")

    run_ref "$home" "$bin" "nvim.file:${project}/src/deep/file.php:7"

    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "$socket"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "kitty_simple_edit_at_line"
    ;;
kitty-nvim-ref-commit-opens-diffview)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    repo=$(make_git_repo "${DOTFILES_TEST_TMP}/repo")
    socket=$(make_live_socket "$repo")

    run_ref "$home" "$bin" "nvim.commit:${repo}:4f4a77b"

    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "$socket"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "kitty_show_commit"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "4f4a77b"
    ;;
kitty-nvim-ref-commit-requires-matching-repository)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    workspace="${DOTFILES_TEST_TMP}/workspace"
    repo=$(make_git_repo "${workspace}/repo")
    make_live_socket "$workspace" >/dev/null

    if run_ref "$home" "$bin" "nvim.commit:${repo}:4f4a77b" 2>"${DOTFILES_TEST_TMP}/stderr.log"; then
        printf 'expected failure for a session outside the cited repository\n' >&2
        exit 1
    fi

    grep -Fq -- "no Neovim session for repository ${repo}" "${DOTFILES_TEST_TMP}/stderr.log"
    [[ ! -f "${DOTFILES_TEST_TMP}/open_in_nvim.args" ]]
    ;;
kitty-nvim-ref-missing-session-notifies)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    project="${DOTFILES_TEST_TMP}/project"
    mkdir -p "$project"
    printf 'line\n' >"${project}/file.php"

    if run_ref "$home" "$bin" "nvim.file:${project}/file.php:214" 2>"${DOTFILES_TEST_TMP}/stderr.log"; then
        printf 'expected failure when no Neovim session is live\n' >&2
        exit 1
    fi

    grep -Fq -- "no Neovim session for ${project}" "${DOTFILES_TEST_TMP}/stderr.log"
    grep -Fq -- "no Neovim session for ${project}" "${DOTFILES_TEST_TMP}/notify-send.args"
    [[ ! -f "${DOTFILES_TEST_TMP}/open_in_nvim.args" ]]
    ;;
kitty-nvim-ref-all-digit-hash-stays-a-commit)
    home=$(make_fake_home)
    bin=$(make_fake_bin)
    repo=$(make_git_repo "${DOTFILES_TEST_TMP}/repo")
    socket=$(make_live_socket "$repo")

    run_ref "$home" "$bin" "nvim.commit:${repo}:1234567"

    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "$socket"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "kitty_show_commit"
    assert_file_contains "${DOTFILES_TEST_TMP}/open_in_nvim.args" "1234567"
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
