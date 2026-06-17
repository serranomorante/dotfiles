#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: renovate dependencies ansible fast
# dotfiles-test-case: renovate-config-json-is-valid
# dotfiles-test-case: renovate-config-is-local-only
# dotfiles-test-case: renovate-config-uses-only-custom-regex-managers
# dotfiles-test-case: renovate-config-has-no-inline-yaml-markers
# dotfiles-test-case: renovate-config-covers-managed-npm-pins
# dotfiles-test-case: renovate-config-covers-runtime-major-lanes
# dotfiles-test-case: renovate-config-covers-vscode-go-releases
# dotfiles-test-case: renovate-config-constrains-mixed-tag-sources
# dotfiles-test-case: renovate-config-keeps-vscode-js-debug-install-scripts-disabled
# dotfiles-test-case: renovate-tool-is-installed-by-ansible
# dotfiles-test-case: renovate-local-apply-helper-is-installed
# dotfiles-test-case: renovate-local-apply-helper-is-exposed-in-lazygit

# Purpose: Verify the local Renovate configuration used to propose version pin updates.

config_file="${DOTFILES_TEST_ROOT}/renovate.json"
dev_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/defaults/main/main.yml"
ai_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/defaults/main/ai.yml"
lang_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/defaults/main.yml"
go_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/140-setup-go-tools.archlinux.yml"
javascript_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/30-lang-tools/tasks/30-setup-javascript-tools.archlinux.yml"
font_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/defaults/main/fonts.vars.yml"
dev_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/175-setup-dependency-update-tools.archlinux.yml"
dev_main_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/main.yml"
local_apply_helper="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/files/dotfiles-renovate-apply"
lazygit_config="${DOTFILES_TEST_ROOT}/lazygit/dot-config/lazygit/config.yml"

json_query() {
    python3 - "$config_file" "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

value = data
for part in sys.argv[2].split("."):
    if part:
        value = value[part]
print(json.dumps(value, sort_keys=True))
PY
}

managed_npm_names() {
    awk '
        /^[[:space:]]*- name:/ {
            name = $0
            sub(/^[[:space:]]*- name:[[:space:]]*/, "", name)
            gsub(/^"|"$/, "", name)
            next
        }
        /^[[:space:]]+version:/ && name != "" {
            print name
            name = ""
        }
        /^[^[:space:]-]/ {
            name = ""
        }
    ' "$dev_defaults" "$ai_defaults" "$lang_defaults" | sort -u
}

renovate_managed_npm_names() {
    python3 - "$config_file" "$dev_defaults" "$ai_defaults" "$lang_defaults" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

pattern = None
for manager in config["customManagers"]:
    if manager.get("datasourceTemplate") == "npm":
        pattern = manager["matchStrings"][0]
        break
if pattern is None:
    raise SystemExit("missing npm manager")

pattern = re.sub(r"\(\?<([A-Za-z_][A-Za-z0-9_]*)>", r"(?P<\1>", pattern)
regex = re.compile(pattern)
names = set()
for path in sys.argv[2:]:
    with open(path, encoding="utf-8") as handle:
        for match in regex.finditer(handle.read()):
            names.add(match.group("depName"))
for name in sorted(names):
    print(name)
PY
}

case "${DOTFILES_TEST_CASE:-}" in
renovate-config-json-is-valid)
    python3 -m json.tool "$config_file" >/dev/null
    ;;
renovate-config-is-local-only)
    [ "$(json_query dependencyDashboard)" = 'false' ]
    [ "$(json_query dependencyDashboardApproval)" = 'false' ]
    ! rg -q '"platform"[[:space:]]*:[[:space:]]*"github"' "$config_file"
    ;;
renovate-config-uses-only-custom-regex-managers)
    [ "$(json_query enabledManagers)" = '["custom.regex"]' ]
    ! rg -q '"datasourceTemplate": "aur"|"datasourceTemplate": "arch"' "$config_file"
    ;;
renovate-config-has-no-inline-yaml-markers)
    ! rg -n '#[[:space:]]*renovate:' "${DOTFILES_TEST_ROOT}/playbooks/roles"
    ;;
renovate-config-covers-managed-npm-pins)
    managed_npm_names >"${DOTFILES_TEST_TMP}/expected-npm.txt"
    renovate_managed_npm_names >"${DOTFILES_TEST_TMP}/actual-npm.txt"
    diff -u "${DOTFILES_TEST_TMP}/expected-npm.txt" "${DOTFILES_TEST_TMP}/actual-npm.txt"
    ;;
renovate-config-covers-runtime-major-lanes)
    rg -Fq '"matchDepTypes": ["node-system-default"]' "$config_file"
    rg -Fq '"allowedVersions": "/^22\\./"' "$config_file"
    rg -Fq '"matchDepTypes": ["node-ansible-language-server"]' "$config_file"
    rg -Fq '"allowedVersions": "/^24\\./"' "$config_file"
    rg -Fq '"matchDepTypes": ["python-ml-runtime"]' "$config_file"
    rg -Fq '"allowedVersions": "/^3\\.14\\./"' "$config_file"
    ! rg -Fq '"matchDepTypes": ["python-piper-runtime"]' "$config_file"
    ;;
renovate-config-covers-vscode-go-releases)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

for manager in config["customManagers"]:
    if manager.get("packageNameTemplate") == "golang/vscode-go":
        assert manager["datasourceTemplate"] == "github-releases"
        assert manager["extractVersionTemplate"] == "^v(?<version>.*)$"
        assert manager["depTypeTemplate"] == "github-release"
        break
else:
    raise SystemExit("missing vscode-go manager")
PY
    rg -q '^vscode_go_version: "[0-9][^"]*"$' "$lang_defaults"
    rg -Fq 'version: v{{ vscode_go_version }}' "$go_tasks"
    rg -Fq 'content: "v{{ vscode_go_version }}\n"' "$go_tasks"
    ! rg -Fq 'release-v{{ vscode_go_version }}' "$go_tasks"
    ;;
renovate-config-constrains-mixed-tag-sources)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

for rule in config["packageRules"]:
    if rule.get("matchPackageNames") == ["microsoft/vscode-js-debug"]:
        assert rule["allowedVersions"] == "/^1\\./"
        break
else:
    raise SystemExit("missing vscode-js-debug package rule")

for rule in config["packageRules"]:
    if rule.get("matchDepNames") == ["yarn"]:
        assert rule["allowedVersions"] == "/^1\\./"
        break
else:
    raise SystemExit("missing yarn package rule")

for manager in config["customManagers"]:
    if manager.get("packageNameTemplate") == "kristoff-it/superhtml":
        assert manager["validationUrlTemplates"] == [
            "https://github.com/kristoff-it/superhtml/releases/download/v{{ newValue }}/x86_64-linux-musl.tar.gz"
        ]
        break
else:
    raise SystemExit("missing superhtml validation URL")
PY
    ;;
renovate-config-keeps-vscode-js-debug-install-scripts-disabled)
    python3 - "$javascript_tasks" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    text = handle.read()

needle = '- name: "[archlinux] Javascript language: install vscode-js-debug npm packages"'
start = text.index(needle)
end = text.index('- name: "[archlinux] Javascript language: build vscode-js-debug"', start)
block = text[start:end]

assert 'NPM_CONFIG_IGNORE_SCRIPTS: "true"' in block
PY
    ;;
renovate-tool-is-installed-by-ansible)
    rg -q 'node_dependency_update_npm_packages:' "$dev_defaults"
    rg -q 'name: renovate' "$dev_defaults"
    rg -Fq 'node_dependency_update_node_version: "{{ node_ansible_language_server_version }}"' "$dev_defaults"
    rg -Fq 'node_dependency_update_npm_prefix: "{{ ansible_facts.env.HOME }}/data/apps/dev-tools/dependency-update-tools/node-{{ node_dependency_update_node_version }}/.npm"' "$dev_defaults"
    rg -q 'tasks_from: npm' "$dev_tasks"
    rg -q 'node_dependency_update_npm_prefix' "$dev_tasks"
    rg -Fq 'update_diff_npm_node_version: "{{ node_dependency_update_node_version }}"' "$dev_tasks"
    rg -q 'remove stale npm package binary symlinks' "$dev_tasks"
    rg -q 'stat.islnk' "$dev_tasks"
    rg -Fq 'node_dependency_update_node_bin_dir }}:$PATH' "$dev_tasks"
    rg -Fq 'cd "{{ ansible_facts.env.HOME }}/dotfiles" || exit 1' "$dev_tasks"
    rg -q -- '--onboarding=false --require-config=required' "$dev_tasks"
    ! rg -q 'Setup dependency update tools: symlink npm package binaries' "$dev_tasks"
    rg -q '175-setup-dependency-update-tools' "$dev_main_tasks"
    ;;
renovate-local-apply-helper-is-installed)
    python3 - "$local_apply_helper" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
    rg -q 'src: dotfiles-renovate-apply' "$dev_tasks"
    rg -Fq 'dest: "{{ node_user_bin_dir }}/dotfiles-renovate-apply"' "$dev_tasks"
    rg -q 'mode: "755"' "$dev_tasks"
    rg -Fq '"github-releases"' "$local_apply_helper"
    rg -Fq '"github-tags"' "$local_apply_helper"
    rg -Fq '"node-version"' "$local_apply_helper"
    rg -Fq '"python-version"' "$local_apply_helper"
    rg -Fq 'minimumReleaseAge' "$local_apply_helper"
    rg -Fq 'RENOVATE_GITHUB_COM_TOKEN' "$local_apply_helper"
    rg -Fq 'dotfiles-github-token' "$local_apply_helper"
    [ -x "${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-github-token" ]
    rg -Fq 'validationUrlTemplates' "$local_apply_helper"
    rg -Fq 'git", "worktree", "add", "-b"' "$local_apply_helper"
    rg -Fq 'fontawesome-free-{{ arch_font_awesome_font_version }}-desktop.zip' "$font_defaults"
    ;;
renovate-local-apply-helper-is-exposed-in-lazygit)
    rg -Fq 'key: "<c-r>"' "$lazygit_config"
    rg -Fq 'description: "Custom: Generate local dependency update branch"' "$lazygit_config"
    rg -Fq 'command: "dotfiles-renovate-apply"' "$lazygit_config"
    rg -Fq 'subprocess: true' "$lazygit_config" || rg -Fq 'output: terminal' "$lazygit_config"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
