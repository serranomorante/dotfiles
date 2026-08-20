#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks calibre ansible shell fast
# dotfiles-test-case: calibre-server-config-allows-local-writes
# dotfiles-test-case: calibre-server-config-is-wired-into-role

# Purpose: Hermetic tests for the private calibre content-server config task
#   (70-45). The task must ensure `local_write true` in the user's
#   server-config.txt as a non-become lineinfile, and main.yml must wire the
#   task file in under the 70-45 tag.

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse the role tasks\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
calibre-server-config-allows-local-writes)
    skip_missing_yaml
    tasks_file="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/45-setup-calibre-config.archlinux.yml"

    python3 - "$tasks_file" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

assert len(tasks) == 1, tasks
task = tasks[0]
assert task["name"].startswith("["), task["name"]
li = task["ansible.builtin.lineinfile"]
assert li["path"] == "{{ ansible_facts.user_dir }}/.config/calibre/server-config.txt", li
assert li["regexp"] == "^local_write", li
assert li["line"] == "local_write true", li
assert li["create"] is True, li
assert "become" not in task, "must run as the user, not become"
PY
    ;;
calibre-server-config-is-wired-into-role)
    skip_missing_yaml
    main_file="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/main.yml"

    python3 - "$main_file" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    blocks = yaml.safe_load(fh)

for block in blocks:
    if block.get("tags") == ["70-45"]:
        found = block["block"][0]
        assert "45-setup-calibre-config" in found["with_first_found"][0]["files"], found
        break
else:
    raise SystemExit("no 70-45 block in main.yml")
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
