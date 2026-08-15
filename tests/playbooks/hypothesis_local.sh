#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: hypothesis nginx ansible pkm fast
# dotfiles-test-case: hypothesis-local-alias-in-hosts-loop
# dotfiles-test-case: hypothesis-local-proxied-by-nginx
# dotfiles-test-case: hypexport-domain-points-at-hypothesis-local
# dotfiles-test-case: hypexport-patch-uses-pkm-venv-python

# Purpose: Verify the self-hosted hypothesis instance is reachable through the
# nginx `hypothesis.local` alias and that hypexport is patched to query that
# alias instead of the public hypothes.is service.

media_proxy="${DOTFILES_TEST_ROOT}/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/40-setup-media-proxy.archlinux.yml"
hpi_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml"

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse the playbook tasks\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
hypothesis-local-alias-in-hosts-loop)
    skip_missing_yaml
    python3 - "$media_proxy" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

for task in tasks:
    if task.get("name") and "ensure /etc/hosts entries" in task["name"]:
        hosts = task.get("loop") or []
        if "hypothesis.local" not in hosts:
            raise SystemExit("hypothesis.local missing from /etc/hosts loop")
        break
else:
    raise SystemExit("hosts task not found")
PY
    ;;
hypothesis-local-proxied-by-nginx)
    skip_missing_yaml
    python3 - "$media_proxy" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

for task in tasks:
    if task.get("name") and "create nginx config for media services" in task["name"]:
        content = task["ansible.builtin.copy"]["content"]
        for needle in (
            "server_name hypothesis.local;",
            "proxy_pass http://127.0.0.1:5000;",
        ):
            if needle not in content:
                raise SystemExit("missing from nginx proxy config: %s" % needle)
        break
else:
    raise SystemExit("nginx proxy task not found")
PY
    ;;
hypexport-domain-points-at-hypothesis-local)
    skip_missing_yaml
    python3 - "$hpi_tasks" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

for task in tasks:
    if task.get("name") and "ensure hypothesis domain points to local instance" in task["name"]:
        replace = task["ansible.builtin.replace"]
        if replace["replace"] != r'\1"hypothesis.local",':
            raise SystemExit("hypexport domain should point at hypothesis.local: %r" % replace["replace"])
        break
else:
    raise SystemExit("hypothesis domain replace task not found")
PY
    refute rg -n 'localhost:5000' "$hpi_tasks"
    ;;
hypexport-patch-uses-pkm-venv-python)
    skip_missing_yaml
    python3 - "$hpi_tasks" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

# The hypexport patch lives in the PKM venv (~/data/apps/PKM), whose python
# version differs from the `h` repo's .python-version. The venv version must be
# derived from the venv itself, never from var_h_python_version.
def find(name_part):
    for task in tasks:
        if task.get("name") and name_part in task["name"]:
            return task
    raise SystemExit("task not found: %s" % name_part)

venv_task = find("get python version from PKM venv")
venv_cmd = venv_task["ansible.builtin.command"]
if "data/apps/PKM/.venv/bin/python" not in venv_cmd:
    raise SystemExit("venv python version task should use the PKM venv python")

for name in (
    "stat hypothesis py file",
    "ensure hypothesis domain points to local instance",
    "replace https",
):
    task = find(name)
    node = task.get("ansible.builtin.stat") or task.get("ansible.builtin.replace")
    path = node.get("path", "")
    if "var_h_python_version" in path:
        raise SystemExit("hypothesis patch path must not use var_h_python_version: %s" % path)
    if "var_pkm_python_version" not in path:
        raise SystemExit("hypothesis patch path must use var_pkm_python_version: %s" % path)
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
