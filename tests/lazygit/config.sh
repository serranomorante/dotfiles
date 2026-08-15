#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: lazygit
# dotfiles-test-tags: lazygit git config shell fast
# dotfiles-test-case: config-valid-yaml
# dotfiles-test-case: reset-author-head
# dotfiles-test-case: reset-author-non-head

# Purpose: Verify the lazygit config custom command that resets the author and
# committer of the selected commit to the gitconfig global user.

lazygit_config="${DOTFILES_TEST_ROOT}/lazygit/dot-config/lazygit/config.yml"

assert_contains() {
    local haystack=$1
    local needle=$2

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'expected to find %s in:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

reset_author_command() {
    awk '
        {
            if ($0 ~ /- key:[[:space:]]*["'\''"]U["'\''"]/) {
                in_block = 1
            } else if ($0 ~ /- key:/) {
                in_block = 0
            }
            if (in_block && $0 ~ /^[[:space:]]*command:/) {
                line = $0
                sub(/^[[:space:]]*command:[[:space:]]*["'\''"]?/, "", line)
                sub(/["'\''"][[:space:]]*$/, "", line)
                print line
                exit
            }
        }
    ' "$lazygit_config"
}

# Runs the declared 'U' command as lazygit would, with the selected commit sha
# substituted for the {{.SelectedCommit.Sha}} placeholder.
run_reset_author() {
    local repo=$1
    local target_sha=$2
    local command_line
    local resolved

    command_line=$(reset_author_command)
    [[ -n "$command_line" ]]
    assert_contains "$command_line" '{{.SelectedCommit.Sha}}'
    resolved="${command_line//\{\{.SelectedCommit.Sha\}\}/$target_sha}"
    (cd "$repo" && bash -c "$resolved")
}

new_repo_with_old_author() {
    local repo="${DOTFILES_TEST_TMP}/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Old User"
    git -C "$repo" config user.email "old@example.com"
    printf 'a\n' >"${repo}/a.txt"
    git -C "$repo" add a.txt
    git -C "$repo" commit -q -m "one"
    printf 'b\n' >"${repo}/b.txt"
    git -C "$repo" add b.txt
    git -C "$repo" commit -q -m "two"
    printf 'c\n' >"${repo}/c.txt"
    git -C "$repo" add c.txt
    git -C "$repo" commit -q -m "three"

    # The gitconfig global user is the identity the reset must land on.
    printf '[user]\n\tname = New User\n\temail = new@example.com\n' \
        >"${DOTFILES_TEST_TMP}/home/.gitconfig"
}

case "${DOTFILES_TEST_CASE:-}" in
config-valid-yaml)
    /usr/bin/python3 - "$lazygit_config" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)

commands = cfg["customCommands"]
reset = [c for c in commands if c.get("key") == "U" and c.get("context") == "commits"]
if len(reset) != 1:
    print(f"expected exactly one 'commits' custom command with key U, got {len(reset)}", file=sys.stderr)
    sys.exit(1)

cmd = reset[0]
desc = cmd["description"]
assert "Reset author/committer" in desc and "selected commit" in desc, desc
assert "{{.SelectedCommit.Sha}}" in cmd["command"], cmd["command"]
assert "--reset-author" in cmd["command"], cmd["command"]
assert "git rebase -i" in cmd["command"], cmd["command"]
assert 'name="$(git config --global user.name)"' in cmd["command"], cmd["command"]
assert 'email="$(git config --global user.email)"' in cmd["command"], cmd["command"]
assert 'git -c user.name="$name" -c user.email="$email"' in cmd["command"], cmd["command"]
assert "--no-edit" in cmd["command"], cmd["command"]
assert "GIT_SEQUENCE_EDITOR" in cmd["command"], cmd["command"]
assert "git rebase --continue" in cmd["command"], cmd["command"]
assert cmd["prompts"][0]["type"] == "confirm", cmd["prompts"]
assert cmd.get("after", {}).get("checkForConflicts") is True, cmd.get("after")
PY
    ;;
reset-author-head)
    new_repo_with_old_author
    repo="${DOTFILES_TEST_TMP}/repo"

    target_sha=$(git -C "$repo" rev-parse HEAD)
    run_reset_author "$repo" "$target_sha"

    author=$(git -C "$repo" log -1 --format='%an <%ae>')
    committer=$(git -C "$repo" log -1 --format='%cn <%ce>')
    [[ "$author" == "New User <new@example.com>" ]]
    [[ "$committer" == "New User <new@example.com>" ]]
    ;;
reset-author-non-head)
    new_repo_with_old_author
    repo="${DOTFILES_TEST_TMP}/repo"

    # Target the middle commit, not HEAD: the cursor may hover any commit.
    target_sha=$(git -C "$repo" rev-parse HEAD~1)
    run_reset_author "$repo" "$target_sha"

    # The rebase rewrites the commit, so its sha changes; assert by position.
    target_author=$(git -C "$repo" log -1 --format='%an <%ae>' HEAD~1)
    target_committer=$(git -C "$repo" log -1 --format='%cn <%ce>' HEAD~1)
    head_author=$(git -C "$repo" log -1 --format='%an <%ae>')
    root_author=$(git -C "$repo" log -1 --format='%an <%ae>' HEAD~2)

    [[ "$target_author" == "New User <new@example.com>" ]]
    [[ "$target_committer" == "New User <new@example.com>" ]]
    # Only the selected commit changes; the commits around it stay untouched.
    [[ "$head_author" == "Old User <old@example.com>" ]]
    [[ "$root_author" == "Old User <old@example.com>" ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
