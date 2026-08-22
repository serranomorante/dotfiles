#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks calibre ansible shell fast
# dotfiles-test-case: calibre-server-config-allows-local-writes
# dotfiles-test-case: calibre-server-config-is-wired-into-role
# dotfiles-test-case: calibre-server-service-is-defined
# dotfiles-test-case: calibre-server-service-library-path-matches-role-defaults
# dotfiles-test-case: calibre-server-service-is-enabled-by-role

# Purpose: Hermetic tests for the private calibre content-server config task
#   (70-45) and the always-on content server user unit. The task must ensure
#   `local_write true` in the user's server-config.txt as a non-become
#   lineinfile, enable and start the stowed calibre-server user service, and
#   main.yml must wire the task file in under the 70-45 tag. The service unit
#   must bind the loopback content server on port 8080 with local writes
#   enabled and gate on the real library directory being mounted.

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

assert len(tasks) == 2, tasks
task = next(t for t in tasks if "ansible.builtin.lineinfile" in t)
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
calibre-server-service-is-defined)
    unit="$DOTFILES_TEST_ROOT/for-my-eyes-only/dot-config/systemd/user/calibre-server.service"
    [ -f "$unit" ]
    grep -Fq 'Description=Calibre content server on 127.0.0.1:8080' "$unit"
    grep -Fq 'ConditionPathIsDirectory=/srv/media/books/calibre-library' "$unit"
    grep -Fq 'ExecStart=/usr/bin/calibre-server --port 8080 --listen-on 127.0.0.1 --enable-local-write /srv/media/books/calibre-library' "$unit"
    grep -Fq 'Restart=on-failure' "$unit"
    grep -Fq 'WantedBy=default.target' "$unit"
    ;;
calibre-server-service-library-path-matches-role-defaults)
    skip_missing_yaml
    unit="$DOTFILES_TEST_ROOT/for-my-eyes-only/dot-config/systemd/user/calibre-server.service"
    vars_file="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/defaults/main/main.vars.yml"

    python3 - "$vars_file" "$unit" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    vars = yaml.safe_load(fh)

library_path = vars["calibre_web_setup"]["library_path"]
unit_src = open(sys.argv[2]).read()
assert "ConditionPathIsDirectory=%s" % library_path in unit_src, unit_src
assert "--enable-local-write %s" % library_path in unit_src, unit_src
PY
    ;;
calibre-server-service-is-enabled-by-role)
    skip_missing_yaml
    tasks_file="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/45-setup-calibre-config.archlinux.yml"

    python3 - "$tasks_file" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

task = next(t for t in tasks if "ansible.builtin.systemd_service" in t)
assert task["name"].startswith("["), task["name"]
svc = task["ansible.builtin.systemd_service"]
assert svc["scope"] == "user", svc
assert svc["name"] == "calibre-server.service", svc
assert svc["enabled"] is True, svc
assert svc["masked"] is False, svc
assert svc["state"] == "started", svc
assert "become" not in task, "user service must not become"
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
