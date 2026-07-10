#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks browser desktop shell fast
# dotfiles-test-case: brave-desktop-enables-experimental-processes-api
# dotfiles-test-case: browser-resource-docs-mention-brave-experimental-processes-api

# Purpose: Guard generated Chromium-family desktop launchers used by browser spike attribution.

browser_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/170-setup-browser-tools.archlinux.yml"
resource_docs="${DOTFILES_TEST_ROOT}/docs/browser-resource-limits.md"

task_block() {
    local file=$1
    local name=$2

    awk -v name="$name" '
        /^- name: / {
            if (in_task) {
                exit
            }
            if (index($0, name)) {
                in_task = 1
            }
        }
        in_task {
            print
        }
    ' "$file"
}

assert_contains() {
    local text=$1
    local expected=$2

    grep -Fq -- "$expected" <<<"$text" || {
        printf 'expected text to contain: %s\n' "$expected" >&2
        printf '%s\n' '--- text ---' >&2
        printf '%s\n' "$text" >&2
        exit 1
    }
}

assert_line_contains() {
    local file=$1
    local expected=$2

    grep -Fq -- "$expected" "$file" || {
        printf 'expected %s to contain: %s\n' "$file" "$expected" >&2
        exit 1
    }
}

case "${DOTFILES_TEST_CASE:-}" in
brave-desktop-enables-experimental-processes-api)
    block=$(task_block "$browser_tasks" "[archlinux] Setup browser tools: ensure brave scale")
    [ -n "$block" ] || {
        printf 'brave desktop task not found in %s\n' "$browser_tasks" >&2
        exit 1
    }

    assert_contains "$block" "Exec={{ ansible_facts.env.HOME }}/bin/app-cgroup-launch brave /usr/bin/brave"
    assert_contains "$block" "--remote-debugging-port=9223"
    assert_contains "$block" "--enable-experimental-extension-apis"
    assert_contains "$block" "--load-extension={{ browser_local_extensions | map(attribute='path') | join(',') }}"
    ;;
browser-resource-docs-mention-brave-experimental-processes-api)
    assert_line_contains "$resource_docs" 'the generated Brave launcher exposes local DevTools on `127.0.0.1:9223` and starts with `--enable-experimental-extension-apis`'
    assert_line_contains "$resource_docs" '`chrome.processes` support'
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
