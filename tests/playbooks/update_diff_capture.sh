#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: update-diff ansible shell git fast
# dotfiles-test-case: update-diff-capture-helper-syntax
# dotfiles-test-case: update-diffs-list-empty-state
# dotfiles-test-case: update-diff-capture-npm-unchanged-does-not-write-manifest
# dotfiles-test-case: update-diff-capture-npm-observed-versions
# dotfiles-test-case: update-diff-capture-npm-version-absent-is-empty
# dotfiles-test-case: update-diff-capture-git-local-repo
# dotfiles-test-case: update-diff-capture-pip-observed-versions
# dotfiles-test-case: update-diff-capture-pip-missing-archive-records-failure
# dotfiles-test-case: update-diff-capture-pip-version-absent-is-empty
# dotfiles-test-case: update-diffs-lists-captured-git-diff
# dotfiles-test-case: update-diffs-list-plain-preserves-tab-output
# dotfiles-test-case: update-diffs-list-color-can-be-forced
# dotfiles-test-case: update-diff-capture-npm-callsites-use-role
# dotfiles-test-case: update-diff-capture-pip-callsites-use-role
# dotfiles-test-case: update-diff-capture-git-floating-callsites-use-role
# dotfiles-test-case: update-diff-capture-records-ok-npm-markers
# dotfiles-test-case: update-diff-capture-does-not-install-stow-github-helpers
# dotfiles-test-case: update-diff-capture-installs-helpers-once
# dotfiles-test-case: update-diff-capture-github-git-tasks-use-token-wrapper

# Purpose: Verify the explicit Ansible update-diff capture helpers and callsite convention.

capture_helper="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/files/update-diff-capture"
viewer_helper="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/files/update-diffs"

make_git_fixture() {
    source_repo="${DOTFILES_TEST_TMP}/source.git-work"
    worktree="${DOTFILES_TEST_TMP}/worktree"
    state_dir="${DOTFILES_TEST_TMP}/state"

    mkdir -p "$source_repo"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.name "Dotfiles Test"
    git -C "$source_repo" config user.email test@example.invalid
    printf 'before\n' >"${source_repo}/file.txt"
    git -C "$source_repo" add file.txt
    git -C "$source_repo" commit -q -m before
    git clone -q "$source_repo" "$worktree"

    printf 'after\n' >"${source_repo}/file.txt"
    git -C "$source_repo" commit -qa -m after
    target_commit=$(git -C "$source_repo" rev-parse HEAD)
}

capture_git_fixture() {
    "$capture_helper" git --state-dir "$state_dir" --scope test --repo "$source_repo" --dest "$worktree" --to "$target_commit"
}

latest_manifest() {
    find "$state_dir/runs" -path '*/manifest.json' -print | sort | tail -n 1
}

manifest_value() {
    local manifest=$1
    local key=$2
    python3 - "$manifest" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(sys.argv[2])
if value is None:
    sys.exit(1)
print(value)
PY
}

assert_manifest_value() {
    local manifest=$1
    local key=$2
    local expected=$3
    local actual
    actual=$(manifest_value "$manifest" "$key")
    if [ "$actual" != "$expected" ]; then
        printf 'expected %s=%s, got %s\n' "$key" "$expected" "$actual" >&2
        exit 1
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
update-diff-capture-helper-syntax)
    bash -n "$capture_helper"
    bash -n "$viewer_helper"
    ;;
update-diffs-list-empty-state)
    UPDATE_DIFF_CAPTURE_STATE_DIR="${DOTFILES_TEST_TMP}/empty" "$viewer_helper" list >"${DOTFILES_TEST_TMP}/list.out"
    [ ! -s "${DOTFILES_TEST_TMP}/list.out" ]
    ;;
update-diff-capture-npm-unchanged-does-not-write-manifest)
    state_dir="${DOTFILES_TEST_TMP}/state"
    prefix="${DOTFILES_TEST_TMP}/prefix"
    fake_npm="${DOTFILES_TEST_TMP}/fake-npm"
    mkdir -p "$prefix"
    cat >"$fake_npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
ls)
    printf '{"dependencies":{"demo":{"version":"1.2.3"}}}\n'
    ;;
pack)
    printf 'pack should not be called for unchanged packages\n' >&2
    exit 1
    ;;
*)
    printf 'unexpected npm command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_npm"
    "$capture_helper" npm --state-dir "$state_dir" --scope test --prefix "$prefix" --name demo --to 1.2.3 --npm-executable "$fake_npm" >"${DOTFILES_TEST_TMP}/capture.out"
    rg -q '^unchanged[[:space:]]+demo[[:space:]]+1\.2\.3$' "${DOTFILES_TEST_TMP}/capture.out"
    [ ! -d "$state_dir/runs" ]
    ;;
update-diff-capture-npm-observed-versions)
    state_dir="${DOTFILES_TEST_TMP}/state"
    prefix="${DOTFILES_TEST_TMP}/prefix"
    fake_npm="${DOTFILES_TEST_TMP}/fake-npm"
    mkdir -p "$prefix"
    cat >"$fake_npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
ls)
    printf '{"dependencies":{"demo":{"version":"2.0.0"}}}\n'
    ;;
pack)
    spec=
    out=.
    while [ "$#" -gt 0 ]; do
        case "$1" in
        pack)
            shift
            ;;
        --pack-destination)
            out=$2
            shift 2
            ;;
        *)
            spec=$1
            shift
            ;;
        esac
    done
    case "${ANSIBLE_FIREJAIL_NPM_WRITABLE_PATHS:-}" in
    *"$out"*) ;;
    *)
        printf 'expected pack destination to be writable: %s\n' "$out" >&2
        exit 1
        ;;
    esac
    version=${spec##*@}
    mkdir -p "$out"
    printf 'demo-%s.tgz\n' "$version"
    tmp=$(mktemp -d)
    mkdir -p "$tmp/package"
    printf '%s\n' "$version" >"$tmp/package/demo.txt"
    tar -czf "$out/demo-$version.tgz" -C "$tmp" package
    rm -rf "$tmp"
    ;;
*)
    printf 'unexpected npm command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_npm"
    "$capture_helper" npm --state-dir "$state_dir" --scope test --prefix "$prefix" --name demo --from 1.0.0 --to 2.0.0 --npm-executable "$fake_npm" >"${DOTFILES_TEST_TMP}/capture.out"
    manifest=$(latest_manifest)
    repo=$(manifest_value "$manifest" repo_path)
    range=$(manifest_value "$manifest" diff_range)

    assert_manifest_value "$manifest" ecosystem npm
    assert_manifest_value "$manifest" status captured
    assert_manifest_value "$manifest" from 1.0.0
    assert_manifest_value "$manifest" to 2.0.0
    [ -d "${repo}/.git" ]
    git -C "$repo" diff --quiet "$range" --exit-code && {
        printf 'expected captured npm diff to be non-empty\n' >&2
        exit 1
    }
    rg -q '2\.0\.0' "$(dirname "$manifest")/diff.patch"
    ;;
update-diff-capture-npm-version-absent-is-empty)
    fake_npm="${DOTFILES_TEST_TMP}/fake-npm"
    cat >"$fake_npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
ls)
    printf '{}\n'
    ;;
*)
    printf 'unexpected npm command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_npm"
    "$capture_helper" npm-version --prefix "${DOTFILES_TEST_TMP}/prefix" --name missing --npm-executable "$fake_npm" >"${DOTFILES_TEST_TMP}/version.out"
    [ ! -s "${DOTFILES_TEST_TMP}/version.out" ]
    ;;
update-diff-capture-git-local-repo)
    make_git_fixture
    capture_git_fixture >"${DOTFILES_TEST_TMP}/capture.out"
    manifest=$(latest_manifest)
    repo=$(manifest_value "$manifest" repo_path)
    range=$(manifest_value "$manifest" diff_range)

    assert_manifest_value "$manifest" ecosystem git
    assert_manifest_value "$manifest" status captured
    assert_manifest_value "$manifest" diff_quality source
    [ -d "${repo}/.git" ]
    git -C "$repo" diff --quiet "$range" --exit-code && {
        printf 'expected captured git diff to be non-empty\n' >&2
        exit 1
    }
    rg -q 'after' "$(dirname "$manifest")/diff.patch"
    ;;
update-diff-capture-pip-observed-versions)
    state_dir="${DOTFILES_TEST_TMP}/state"
    venv="${DOTFILES_TEST_TMP}/venv"
    fake_pip="${DOTFILES_TEST_TMP}/fake-pip"
    mkdir -p "$venv"
    cat >"$fake_pip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
download)
    spec=
    out=
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --no-deps)
            shift
            ;;
        -d)
            out=$2
            shift 2
            ;;
        download)
            shift
            ;;
        *)
            spec=$1
            shift
            ;;
        esac
    done
    case "${ANSIBLE_FIREJAIL_PIP_WRITABLE_PATHS:-}" in
    *"$out"*) ;;
    *)
        printf 'expected pip download destination to be writable: %s\n' "$out" >&2
        exit 1
        ;;
    esac
    version=${spec##*==}
    mkdir -p "$out"
    tmp=$(mktemp -d)
    printf '%s\n' "$version" >"$tmp/demo.txt"
    tar -czf "$out/demo-$version.tar.gz" -C "$tmp" .
    rm -rf "$tmp"
    ;;
show)
    printf 'Name: demo\nVersion: 2.0.0\n'
    ;;
*)
    printf 'unexpected pip command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_pip"
    "$capture_helper" pip --state-dir "$state_dir" --scope test --venv "$venv" --name demo --from 1.0.0 --to 2.0.0 --pip-executable "$fake_pip" >"${DOTFILES_TEST_TMP}/capture.out"
    manifest=$(latest_manifest)
    repo=$(manifest_value "$manifest" repo_path)
    range=$(manifest_value "$manifest" diff_range)

    assert_manifest_value "$manifest" ecosystem pip
    assert_manifest_value "$manifest" status captured
    assert_manifest_value "$manifest" from 1.0.0
    assert_manifest_value "$manifest" to 2.0.0
    [ -d "${repo}/.git" ]
    git -C "$repo" diff --quiet "$range" --exit-code && {
        printf 'expected captured pip diff to be non-empty\n' >&2
        exit 1
    }
    rg -q '2\.0\.0' "$(dirname "$manifest")/diff.patch"
    ;;
update-diff-capture-pip-missing-archive-records-failure)
    state_dir="${DOTFILES_TEST_TMP}/state"
    venv="${DOTFILES_TEST_TMP}/venv"
    fake_pip="${DOTFILES_TEST_TMP}/fake-pip"
    mkdir -p "$venv"
    cat >"$fake_pip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
download)
    out=
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -d)
            out=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    case "${ANSIBLE_FIREJAIL_PIP_WRITABLE_PATHS:-}" in
    *"$out"*) ;;
    *)
        printf 'expected pip download destination to be writable: %s\n' "$out" >&2
        exit 1
        ;;
    esac
    mkdir -p "$out"
    ;;
show)
    printf 'Name: demo\nVersion: 2.0.0\n'
    ;;
*)
    printf 'unexpected pip command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_pip"
    "$capture_helper" pip --state-dir "$state_dir" --scope test --venv "$venv" --name demo --from 1.0.0 --to 2.0.0 --pip-executable "$fake_pip" >"${DOTFILES_TEST_TMP}/capture.out"
    manifest=$(latest_manifest)

    assert_manifest_value "$manifest" ecosystem pip
    assert_manifest_value "$manifest" status failed
    assert_manifest_value "$manifest" diff_quality metadata-only
    assert_manifest_value "$manifest" from 1.0.0
    assert_manifest_value "$manifest" to 2.0.0
    [ ! -d "$(dirname "$manifest")/repo/.git" ]
    rg -q 'pip download produced no archive' "$(dirname "$manifest")/failure.log"
    rg -q '^failed[[:space:]]+demo[[:space:]]+1\.0\.0 -> 2\.0\.0[[:space:]]+' "${DOTFILES_TEST_TMP}/capture.out"
    ;;
update-diff-capture-pip-version-absent-is-empty)
    fake_pip="${DOTFILES_TEST_TMP}/fake-pip"
    cat >"$fake_pip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
show)
    exit 1
    ;;
*)
    printf 'unexpected pip command: %s\n' "$1" >&2
    exit 1
    ;;
esac
SH
    chmod +x "$fake_pip"
    "$capture_helper" pip-version --venv "${DOTFILES_TEST_TMP}/venv" --name missing --pip-executable "$fake_pip" >"${DOTFILES_TEST_TMP}/version.out"
    [ ! -s "${DOTFILES_TEST_TMP}/version.out" ]
    ;;
update-diffs-lists-captured-git-diff)
    make_git_fixture
    capture_git_fixture >/dev/null
    UPDATE_DIFF_CAPTURE_STATE_DIR="$state_dir" "$viewer_helper" list >"${DOTFILES_TEST_TMP}/list.out"
    rg -q '^git[[:space:]]+worktree[[:space:]]+' "${DOTFILES_TEST_TMP}/list.out"
    rg -q 'captured' "${DOTFILES_TEST_TMP}/list.out"
    ;;
update-diffs-list-plain-preserves-tab-output)
    make_git_fixture
    capture_git_fixture >/dev/null
    UPDATE_DIFF_CAPTURE_STATE_DIR="$state_dir" "$viewer_helper" list --plain >"${DOTFILES_TEST_TMP}/plain.out"
    rg -q $'^git\tworktree\t[0-9a-f]+ -> [0-9a-f]+\tcaptured\t' "${DOTFILES_TEST_TMP}/plain.out"
    ! grep -q "$(printf '\033')\\[" "${DOTFILES_TEST_TMP}/plain.out"
    ;;
update-diffs-list-color-can-be-forced)
    make_git_fixture
    capture_git_fixture >/dev/null
    UPDATE_DIFF_CAPTURE_STATE_DIR="$state_dir" "$viewer_helper" list --color >"${DOTFILES_TEST_TMP}/color.out"
    grep -q "$(printf '\033')\\[32mcaptured$(printf '\033')\\[0m" "${DOTFILES_TEST_TMP}/color.out"
    grep -q "$(printf '\033')\\[34mgit$(printf '\033')\\[0m" "${DOTFILES_TEST_TMP}/color.out"
    ;;
update-diff-capture-npm-callsites-use-role)
    python3 - "${DOTFILES_TEST_ROOT}/playbooks/roles" <<'PY'
import pathlib
import sys
import yaml

roles = pathlib.Path(sys.argv[1])
violations = []

def walk_tasks(value):
    if isinstance(value, list):
        for item in value:
            yield from walk_tasks(item)
    elif isinstance(value, dict):
        if "community.general.npm" in value or "npm" in value:
            yield value
        for key in ("block", "rescue", "always"):
            yield from walk_tasks(value.get(key, []))

for path in roles.rglob("*.yml"):
    if "update-diff-capture/tasks/npm.yml" in str(path):
        continue
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    for task in walk_tasks(data):
        module = task.get("community.general.npm") or task.get("npm")
        if not isinstance(module, dict):
            continue
        if "name" in module and module.get("state") != "absent":
            if path.name.endswith(".macosx.yml") and "volta run" in str(module.get("executable", "")):
                continue
            violations.append(f"{path}: {task.get('name', '<unnamed>')}")

if violations:
    print("direct global npm installs must use update-diff-capture:", file=sys.stderr)
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
PY
    for file in \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/170-setup-ai-tools.archlinux.yml" \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/30-setup-javascript-tools.archlinux.yml" \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/90-setup-yaml-tools.archlinux.yml" \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/100-setup-markdown-tools.archlinux.yml"
    do
        rg -q 'tasks_from: npm' "$file"
        rg -q 'name: update-diff-capture' "$file"
    done
    ;;
update-diff-capture-pip-callsites-use-role)
    rg -n 'ansible\.builtin\.pip:' "${DOTFILES_TEST_ROOT}/playbooks/roles" -g '*.yml' >"${DOTFILES_TEST_TMP}/pip-callsites.out" || true
    ! rg -q -v 'roles/update-diff-capture/tasks/pip\.yml:' "${DOTFILES_TEST_TMP}/pip-callsites.out"
    rg -q 'tasks_from: pip' "${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/70-setup-python-tools.archlinux.yml"
    rg -q 'tasks_from: pip' "${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/100-setup-markdown-tools.archlinux.yml"
    rg -q 'update_diff_pip_state: latest' "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/150-setup-persistence-tools.archlinux.yml"
    ;;
update-diff-capture-git-floating-callsites-use-role)
    python3 - "${DOTFILES_TEST_ROOT}/playbooks/roles" <<'PY'
import pathlib
import sys
import yaml

roles = pathlib.Path(sys.argv[1])
allowed = {
    "https://github.com/serranomorante/dotfiles.git",
    "https://github.com/Ashark/davinci-resolve-checker",
}
violations = []

def walk_tasks(value):
    if isinstance(value, list):
        for item in value:
            yield from walk_tasks(item)
    elif isinstance(value, dict):
        if "ansible.builtin.git" in value or "git" in value:
            yield value
        for key in ("block", "rescue", "always"):
            yield from walk_tasks(value.get(key, []))

def is_floating(version):
    text = str(version)
    return (
        version is None
        or text in {"HEAD", "head", "main", "master"}
        or "default('HEAD')" in text
        or 'default("HEAD")' in text
    )

for path in roles.rglob("*.yml"):
    if "update-diff-capture/tasks/git.yml" in str(path):
        continue
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    for task in walk_tasks(data):
        module = task.get("ansible.builtin.git") or task.get("git")
        if not isinstance(module, dict):
            continue
        repo = str(module.get("repo", ""))
        if repo in allowed:
            continue
        if is_floating(module.get("version")):
            violations.append(f"{path}: {task.get('name', '<unnamed>')} -> {repo}")

if violations:
    print("floating git checkouts must use update-diff-capture:", file=sys.stderr)
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
PY
    rg -q 'tasks_from: git' "${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/60-setup-editor-tools.archlinux.yml"
    rg -q 'tasks_from: git' "${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/40-setup-keyboard-tools.archlinux.yml"
    rg -q 'tasks_from: git' "${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml"
    ;;
update-diff-capture-records-ok-npm-markers)
    npm_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/npm.yml"
    pip_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/pip.yml"

    rg -q 'not item\.skipped \| default\(false\)' "$npm_tasks"
    rg -q 'not item\.failed \| default\(false\)' "$npm_tasks"
    rg -q 'not item\.skipped \| default\(false\)' "$pip_tasks"
    rg -q 'not item\.failed \| default\(false\)' "$pip_tasks"
    rg -q 'read versions before install' "$npm_tasks"
    rg -q 'archive observed package diffs' "$npm_tasks"
    rg -q 'read versions before install' "$pip_tasks"
    rg -q 'archive observed package diffs' "$pip_tasks"
    ! rg -q 'item\.changed \| default\(false\)' "$npm_tasks" "$pip_tasks"
    ;;
update-diff-capture-does-not-install-stow-github-helpers)
    install_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/install.yml"
    git_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/git.yml"

    ! rg -q 'dotfiles-github-token|dotfiles-github-askpass|dotfiles-github-git' "$install_tasks"
    rg -Fq 'executable: "{{ playbook_dir }}/../utilities/bin/dotfiles-github-git"' "$git_tasks"
    rg -Fq 'remote_git "$repo_url" clone -q --mirror "$repo_url" "$cache"' "$capture_helper"
    rg -Fq 'remote_git "$repo_url" -C "$cache" fetch -q --tags --prune origin' "$capture_helper"
    ;;
update-diff-capture-installs-helpers-once)
    for tasks in \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/npm.yml" \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/pip.yml" \
        "${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/git.yml"
    do
        rg -q 'include_tasks: install\.yml' "$tasks"
        rg -q 'not update_diff_capture_helpers_installed \| default\(false\)' "$tasks"
        rg -q 'update_diff_capture_scope \| default' "$tasks"
    done
    rg -q 'update_diff_capture_helpers_installed: true' "${DOTFILES_TEST_ROOT}/playbooks/roles/update-diff-capture/tasks/install.yml"
    ;;
update-diff-capture-github-git-tasks-use-token-wrapper)
    python3 - "${DOTFILES_TEST_ROOT}/playbooks/roles" <<'PY'
import pathlib
import sys
import yaml

roles = pathlib.Path(sys.argv[1])
bootstrap_repos = {
    "https://github.com/serranomorante/dotfiles.git",
}
github_repo_vars = {
    "{{ arch_wineasio_setup.repo }}",
}
violations = []

def walk_tasks(value):
    if isinstance(value, list):
        for item in value:
            yield from walk_tasks(item)
    elif isinstance(value, dict):
        if "ansible.builtin.git" in value or "git" in value:
            yield value
        for key in ("block", "rescue", "always"):
            yield from walk_tasks(value.get(key, []))

for path in roles.rglob("*.yml"):
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    for task in walk_tasks(data):
        module = task.get("ansible.builtin.git") or task.get("git")
        if not isinstance(module, dict):
            continue
        repo = str(module.get("repo", ""))
        if repo in bootstrap_repos:
            continue
        if "github.com" not in repo and repo not in github_repo_vars:
            continue
        executable = str(module.get("executable", ""))
        if "dotfiles-github-git" not in executable:
            violations.append(f"{path}: {task.get('name', '<unnamed>')} -> {repo}")

if violations:
    print("GitHub git tasks must use dotfiles-github-git:", file=sys.stderr)
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
