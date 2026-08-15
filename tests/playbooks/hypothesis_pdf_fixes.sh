#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: hypothesis ansible pkm
# dotfiles-test-case: hypothesis-pdf-fixes-patch-version-agnostic
# dotfiles-test-case: hypothesis-pdf-fixes-patch-covers-null-guard
# dotfiles-test-case: hypothesis-pdf-fixes-marker-contract-version-pinned
# dotfiles-test-case: hypothesis-pdf-fixes-tarball-name-encodes-contract
# dotfiles-test-case: hypothesis-pdf-fixes-verification-gates-marker
# dotfiles-test-case: hypothesis-pdf-fixes-alerts-nonfatally

# Purpose: Verify the hypothesis client PDF-fixes pipeline stays wired across
# extension version bumps: version-agnostic patch, verified application,
# non-fatal dunst alert, and marker gating.

hp_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml"
hp_files="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/files"
hp_defaults="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/defaults/main.yml"
patch_file="${hp_files}/hypothesis-client-pdf-fixes.patch"

# Assert the first task whose name contains $1 matches every expectation.
# Expectation forms:
#   key=value                  top-level task key (value case-insensitive)
#   module:key=value           key inside a module mapping
#   module=value               module whose value is a plain string
# Values starting with "re:" are regex-searched; the rest compare ignoring case.
task_has() {
    local needle=$1
    shift
    python3 - "$hp_tasks" "$needle" "$@" <<'PY'
import re
import sys
import yaml

path, needle, *expectations = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    tasks = yaml.safe_load(handle)
for task in tasks:
    if needle in str(task.get("name", "")):
        for expectation in expectations:
            first_eq = expectation.find("=")
            first_colon = expectation.find(":")
            module = None
            if first_eq != -1 and first_colon != -1 and first_colon < first_eq:
                module, rest = expectation.split(":", 1)
                node = task.get(module)
                if not isinstance(node, dict):
                    print(f"{module} missing in {task.get('name')}", file=sys.stderr)
                    sys.exit(1)
            else:
                rest = expectation
                node = task
            key, _, value = rest.partition("=")
            if key not in node:
                print(f"{key} missing in {task.get('name')}", file=sys.stderr)
                sys.exit(1)
            actual = node[key]
            if isinstance(value, str) and value.startswith("re:"):
                if not re.search(value[3:], str(actual)):
                    print(f"{key}={actual!r} does not match {value}", file=sys.stderr)
                    sys.exit(1)
            elif str(actual).lower() != str(value).lower():
                print(f"{key}={actual!r} != {value}", file=sys.stderr)
                sys.exit(1)
        sys.exit(0)
print(f"task not found: {needle}", file=sys.stderr)
sys.exit(1)
PY
}

case "${DOTFILES_TEST_CASE:-}" in
hypothesis-pdf-fixes-patch-version-agnostic)
    python3 -c "import yaml; yaml.safe_load(open('${hp_tasks}')); yaml.safe_load(open('${hp_defaults}'))"
    task_has "patch hypothesis client PDF source fixes" \
        "ansible.posix.patch:src=hypothesis-client-pdf-fixes.patch"
    [ -f "$patch_file" ]
    refute rg -n 'hypothesis-client-v.*pdf-fixes\.patch' "$hp_tasks"
    [ -z "$(find "$hp_files" -maxdepth 1 -name 'hypothesis-client-v*-pdf-fixes.patch' -print)" ]
    ;;
hypothesis-pdf-fixes-patch-covers-null-guard)
    rg -q 'if \(!app\.pdfDocument\)' "$patch_file"
    rg -q 'getDownloadInfo' "$patch_file"
    rg -q 'pollTimer' "$patch_file"
    rg -q 'getPage\(pageNumber' "$patch_file"
    rg -q 'Unable to load PDF page' "$patch_file"
    rg -q 'cloneRange' "$patch_file"
    ;;
hypothesis-pdf-fixes-marker-contract-version-pinned)
    task_has "set hypothesis client marker facts" \
        "ansible.builtin.set_fact:hypothesis_client_marker=re:v\{\{ hypothesis_client_version \}\}:\{\{ hypothesis_client_contract \}\}"
    refute rg -n 'pdf-fixes-v1\b|pdf-fixes-v2\b' "$hp_tasks"
    rg -q 'hypothesis_client_version: "\{\{ hypothesis_browser_extension_version \}\}"' "$hp_defaults"
    rg -q 'hypothesis_client_contract: pdf-fixes-v[0-9]+' "$hp_defaults"
    ;;
hypothesis-pdf-fixes-tarball-name-encodes-contract)
    rg -q 'dist/hypothesis-\{\{ hypothesis_client_version \}\}-\{\{ hypothesis_client_contract \}\}-local\.tgz' "$hp_tasks"
    rg -q 'file:\.\./client/dist/hypothesis-\{\{ hypothesis_client_version \}\}-\{\{ hypothesis_client_contract \}\}-local\.tgz' "$hp_tasks"
    refute rg -n 'hypothesis-\{\{ hypothesis_client_version \}\}-local\.tgz' "$hp_tasks"
    ;;
hypothesis-pdf-fixes-verification-gates-marker)
    task_has "patch hypothesis client PDF source fixes" \
        "failed_when=false"
    task_has "check hypothesis client PDF fixes applied" \
        "ansible.builtin.command:argv=re:pdf-metadata\.ts" \
        "ansible.builtin.command:argv=re:if \(!app\.pdfDocument\)" \
        "failed_when=false"
    task_has "record hypothesis client marker" \
        "when=re:hypothesis_client_pdf_fixes_ok"
    ;;
hypothesis-pdf-fixes-alerts-nonfatally)
    task_has "alert hypothesis client PDF fixes missing" \
        "ansible.builtin.shell=re:dunstify" \
        "changed_when=false" \
        "failed_when=false" \
        "when=re:hypothesis_client_pdf_fixes_ok" \
        "when=re:is_x_display_session"
    rg -q 'ansible-hypothesis' "$hp_tasks"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
