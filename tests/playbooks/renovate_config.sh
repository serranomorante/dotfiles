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
# dotfiles-test-case: renovate-config-covers-reaper-download-page
# dotfiles-test-case: renovate-config-covers-music-production-release-assets
# dotfiles-test-case: renovate-config-keeps-vscode-js-debug-install-scripts-disabled
# dotfiles-test-case: renovate-config-covers-hypothesis-branch-pins
# dotfiles-test-case: renovate-config-covers-pkm-dependency-pins
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
music_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/defaults/main/music-production.vars.yml"
dev_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/175-setup-dependency-update-tools.archlinux.yml"
dev_main_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/tasks/main.yml"
pkm_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/defaults/main.yml"
hpi_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml"
via_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/25-setup-via.archlinux.yml"
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
    refute rg -q '"platform"[[:space:]]*:[[:space:]]*"github"' "$config_file"
    ;;
renovate-config-uses-only-custom-regex-managers)
    [ "$(json_query enabledManagers)" = '["custom.regex"]' ]
    refute rg -q '"datasourceTemplate": "aur"|"datasourceTemplate": "arch"' "$config_file"
    ;;
renovate-config-has-no-inline-yaml-markers)
    refute rg -n '#[[:space:]]*renovate:' "${DOTFILES_TEST_ROOT}/playbooks/roles"
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
    refute rg -Fq '"matchDepTypes": ["python-piper-runtime"]' "$config_file"
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
    refute rg -Fq 'release-v{{ vscode_go_version }}' "$go_tasks"
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
renovate-config-covers-reaper-download-page)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

datasource = config["customDatasources"]["reaper-downloads"]
assert datasource["defaultRegistryUrlTemplate"] == "https://www.reaper.fm/download.php"
assert datasource["format"] == "html"

for manager in config["customManagers"]:
    if manager.get("depNameTemplate") == "reaper-windows-x64":
        assert manager["datasourceTemplate"] == "custom.reaper-downloads"
        assert manager["extractVersionTemplate"] == "^files\\/7\\.x\\/reaper(?<version>\\d+)_x64-install\\.exe$"
        assert manager["validationUrlTemplates"] == [
            "https://www.reaper.fm/files/7.x/reaper{{ newValue }}_x64-install.exe"
        ]
        assert manager["depTypeTemplate"] == "vendor-html-release-asset"
        break
else:
    raise SystemExit("missing REAPER manager")
PY
    rg -q 'arch_reaper_wine_setup:' "$music_defaults"
    rg -q 'version: "[0-9][0-9][0-9]"' "$music_defaults"
    rg -Fq '"custom."' "$local_apply_helper"
    rg -Fq 'LinkParser' "$local_apply_helper"
    ;;
renovate-config-covers-music-production-release-assets)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

sws_datasource = config["customDatasources"]["sws-pre-release-downloads"]
assert sws_datasource["defaultRegistryUrlTemplate"] == "https://www.sws-extension.org/download/pre-release/"
assert sws_datasource["format"] == "html"

assert all(manager.get("depNameTemplate") != "pipeasio" for manager in config["customManagers"])

for manager in config["customManagers"]:
    if manager.get("depNameTemplate") == "sws-extension-windows-x64":
        assert manager["datasourceTemplate"] == "custom.sws-pre-release-downloads"
        assert manager["extractVersionTemplate"] == "^sws-(?<version>\\d+\\.\\d+\\.\\d+\\.\\d+)-Windows-x64-[0-9a-f]+\\.exe$"
        assert manager["validationUrlTemplates"] == [
            "https://www.sws-extension.org/download/featured/sws-{{ newValue }}-Windows-x64.exe"
        ]
        break
else:
    raise SystemExit("missing SWS manager")

for manager in config["customManagers"]:
    if manager.get("depNameTemplate") == "helgobox":
        assert manager["datasourceTemplate"] == "github-releases"
        assert manager["validationUrlTemplates"] == [
            "https://github.com/helgoboss/helgobox/releases/download/v{{ newValue }}/helgobox-linux-x86_64.so",
            "https://github.com/helgoboss/helgobox/releases/download/v{{ newValue }}/reaper_helgobox-linux-x86_64.so",
            "https://github.com/helgoboss/helgobox/releases/download/v{{ newValue }}/helgobox-windows-x86_64.dll",
            "https://github.com/helgoboss/helgobox/releases/download/v{{ newValue }}/reaper_helgobox-windows-x86_64.dll",
        ]
        break
else:
    raise SystemExit("missing Helgobox manager")
PY
    rg -q 'arch_pipeasio_setup:' "$music_defaults"
    refute rg -q 'M0n7y5/pipeasio|arch_pipeasio_setup\.version|pipeasio-[0-9][.0-9]*' "$music_defaults"
    rg -q 'arch_reaper_sws_extension_setup:' "$music_defaults"
    rg -q 'arch_helgobox_setup:' "$music_defaults"
    ;;
renovate-config-keeps-vscode-js-debug-install-scripts-disabled)
    python3 - "$javascript_tasks" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    text = handle.read()

needle = '- name: "[{{ user_os }}] Javascript language: install vscode-js-debug npm packages"'
start = text.index(needle)
end = text.index('- name: "[{{ user_os }}] Javascript language: build vscode-js-debug"', start)
block = text[start:end]

assert 'NPM_CONFIG_IGNORE_SCRIPTS: "true"' in block
PY
    ;;
renovate-config-covers-hypothesis-branch-pins)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

    expected = {
        "hypothesis/h": ("hypothesis-h", "git-refs", "github-branch"),
        "hypothesis/bouncer": ("hypothesis-bouncer", "git-refs", "github-branch"),
        "hypothesis/via": ("hypothesis-via", "git-refs", "github-branch"),
        "hypothesis/viahtml": ("hypothesis-viahtml", "git-refs", "github-branch"),
    }
found = {}
for manager in config["customManagers"]:
    package = manager.get("packageNameTemplate")
    if package in expected:
        found[package] = (
            manager.get("depNameTemplate"),
            manager.get("datasourceTemplate"),
            manager.get("depTypeTemplate"),
        )

for package, wanted in expected.items():
    assert found.get(package) == wanted, f"{package}: expected {wanted}, got {found.get(package)}"

for manager in config["customManagers"]:
    if manager.get("packageNameTemplate") == "hypothesis/browser-extension":
        assert manager["datasourceTemplate"] == "github-tags"
        break
else:
    raise SystemExit("missing hypothesis browser-extension manager")
PY
    rg -q '^hypothesis_h_version: [0-9a-f]{40}$' "$pkm_defaults"
    rg -q '^hypothesis_bouncer_version: [0-9a-f]{40}$' "$pkm_defaults"
    rg -q '^hypothesis_via_version: [0-9a-f]{40}$' "$pkm_defaults"
    rg -q '^hypothesis_viahtml_version: [0-9a-f]{40}$' "$pkm_defaults"
    rg -Fq 'version: "{{ hypothesis_h_version }}"' "$hpi_tasks"
    rg -Fq 'version: "{{ hypothesis_bouncer_version }}"' "$hpi_tasks"
    rg -Fq 'version: "{{ hypothesis_via_version }}"' "$via_tasks"
    rg -Fq 'version: "{{ hypothesis_viahtml_version }}"' "$via_tasks"
    refute rg -Fq 'update_diff_git_version: main' "$hpi_tasks"
    rg -q 'h_setup_marker: "h:\{\{ hypothesis_h_version \}\}:bouncer:\{\{ hypothesis_bouncer_version \}\}:h-patches-v\d+"' "$hpi_tasks"
    rg -q 'via_setup_marker: "via:\{\{ hypothesis_via_version \}\}:viahtml:\{\{ hypothesis_viahtml_version \}\}:via-patches-v\d+"' "$via_tasks"
    ;;
renovate-config-covers-pkm-dependency-pins)
    python3 - "$config_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

pypi_manager = None
hypexport_manager = None
for manager in config["customManagers"]:
    package = manager.get("packageNameTemplate")
    if manager.get("datasourceTemplate") == "pypi" and "promnesia" in manager["matchStrings"][0]:
        pypi_manager = manager
    if package == "karlicoss/hypexport":
        hypexport_manager = manager

assert pypi_manager is not None, "missing PKM pypi manager"
assert pypi_manager["datasourceTemplate"] == "pypi"
assert pypi_manager["versioningTemplate"] == "pep440"
for name in ("promnesia", "browserexport", "cachew"):
    assert name in pypi_manager["matchStrings"][0], f"pypi manager missing {name}"

assert hypexport_manager is not None, "missing hypexport git-refs manager"
assert hypexport_manager["datasourceTemplate"] == "git-refs"
assert hypexport_manager["depTypeTemplate"] == "github-branch"
PY
    rg -q '^pkm_promnesia_version: [0-9][0-9.]*$' "$pkm_defaults"
    rg -q '^pkm_browserexport_version: [0-9][0-9.]*$' "$pkm_defaults"
    rg -q '^pkm_cachew_version: [0-9][0-9.]*$' "$pkm_defaults"
    rg -q '^pkm_hypexport_version: [0-9a-f]{40}$' "$pkm_defaults"
    rg -Fq 'version: "{{ pkm_promnesia_version }}"' "$hpi_tasks"
    rg -Fq 'version: "{{ pkm_browserexport_version }}"' "$hpi_tasks"
    rg -Fq 'version: "{{ pkm_cachew_version }}"' "$hpi_tasks"
    rg -Fq 'hypexport[export] @ git+https://github.com/karlicoss/hypexport@{{ pkm_hypexport_version }}' "$hpi_tasks"
    rg -Fq 'lookup_name: HPI' "$hpi_tasks"
    rg -Fq 'state: latest' "$hpi_tasks"
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
    refute rg -q 'Setup dependency update tools: symlink npm package binaries' "$dev_tasks"
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
    rg -Fq '"git-refs"' "$local_apply_helper"
    rg -Fq '"node-version"' "$local_apply_helper"
    rg -Fq '"python-version"' "$local_apply_helper"
    rg -Fq 'minimumReleaseAge' "$local_apply_helper"
    rg -Fq 'RENOVATE_GITHUB_COM_TOKEN' "$local_apply_helper"
    rg -Fq 'dotfiles-github-token' "$local_apply_helper"
    [ -x "${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-github-token" ]
    rg -Fq 'validationUrlTemplates' "$local_apply_helper"
    rg -Fq 'git", "worktree", "add", "-b"' "$local_apply_helper"
    rg -Fq 'fontawesome-free' "$font_defaults"
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
