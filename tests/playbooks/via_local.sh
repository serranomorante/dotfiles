#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: hypothesis via nginx ansible pkm fast
# dotfiles-test-case: via-local-alias-in-hosts-loop
# dotfiles-test-case: via-local-proxied-by-nginx
# dotfiles-test-case: via-self-hosted-services-wired
# dotfiles-test-case: via-restriction-patch-wired
# dotfiles-test-case: via-oauth-client-wired

# Purpose: Verify the self-hosted via and viahtml readers are reachable through
# the nginx `via.local` and `viahtml.local` aliases and are run by the fj-node
# systemd user services, mirroring the hypothesis.local setup.

media_proxy="${DOTFILES_TEST_ROOT}/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/40-setup-media-proxy.archlinux.yml"
systemd_dir="${DOTFILES_TEST_ROOT}/PKM/dot-config/systemd/user"
via_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/25-setup-via.archlinux.yml"
via_files="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/files"
hpi_tasks="${DOTFILES_TEST_ROOT}/playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml"

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse the playbook tasks\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
via-local-alias-in-hosts-loop)
    skip_missing_yaml
    python3 - "$media_proxy" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

for task in tasks:
    if task.get("name") and "ensure /etc/hosts entries" in task["name"]:
        hosts = task.get("loop") or []
        for alias in ("via.local", "viahtml.local"):
            if alias not in hosts:
                raise SystemExit(f"{alias} missing from /etc/hosts loop")
        break
else:
    raise SystemExit("hosts task not found")
PY
    ;;
via-local-proxied-by-nginx)
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
            "server_name via.local;",
            "proxy_pass http://127.0.0.1:9083;",
            "server_name viahtml.local;",
            "proxy_pass http://127.0.0.1:9085;",
        ):
            if needle not in content:
                raise SystemExit("missing from nginx proxy config: %s" % needle)
        break
else:
    raise SystemExit("nginx proxy task not found")
PY
    ;;
via-self-hosted-services-wired)
    for service in via-self-hosted viahtml-self-hosted; do
        unit="${systemd_dir}/${service}.service"
        [ -f "$unit" ] || { printf 'missing service unit: %s\n' "$unit" >&2; exit 1; }
        rg -Fq 'fj-node online' "$unit"
        rg -Fq 'make dev' "$unit"
        rg -Fq 'FJ_NODE_PROFILE=fj-node-hypothesis.profile' "$unit"
    done
    rg -Fq 'VIA_DISABLE_AUTHENTICATION=1' "${systemd_dir}/viahtml-self-hosted.service"
    client_pkg="${systemd_dir}/hypothesis-client-package.service"
    [ -f "$client_pkg" ] || { printf 'missing client package unit: %s\n' "$client_pkg" >&2; exit 1; }
    rg -Fq 'gulp serve-package' "$client_pkg"
    rg -Fq 'FJ_NODE_PROFILE=fj-node-hypothesis.profile' "$client_pkg"
    ;;
via-restriction-patch-wired)
    patch_file="${via_files}/hypothesis-via-disable-restriction.patch"
    [ -f "$patch_file" ] || { printf 'missing restriction patch: %s\n' "$patch_file" >&2; exit 1; }
    rg -Fq 'hypothesis-via-disable-restriction.patch' "$via_tasks"
    rg -Fq 'request_has_valid_token' "$patch_file"
    rg -Fq 'request_is_valid(' "$patch_file"
    banner_patch="${via_files}/hypothesis-via-remove-decommission-banner.patch"
    [ -f "$banner_patch" ] || { printf 'missing banner patch: %s\n' "$banner_patch" >&2; exit 1; }
    rg -Fq 'hypothesis-via-remove-decommission-banner.patch' "$via_tasks"
    rg -Fq 'decommission-banner' "$banner_patch"
    rg -q 'via_setup_marker: "via:\{\{ hypothesis_via_version \}\}:viahtml:\{\{ hypothesis_viahtml_version \}\}:via-patches-v3"' "$via_tasks"
    ;;
via-oauth-client-wired)
    rg -Fq 'register via authclient exists' "$hpi_tasks"
    rg -Fq 'create via OAuth client' "$hpi_tasks"
    rg -Fq -- '--redirect-uri' "$hpi_tasks"
    rg -Fq 'http://localhost:5000' "$hpi_tasks"
    rg -Fq -- '--grant-type' "$hpi_tasks"
    rg -Fq "response_type = 'code', trusted = true" "$hpi_tasks"
    rg -Fq 'set h client oauth id' "$hpi_tasks"
    rg -Fq 'h.client_oauth_id: {{ via_oauth_client_id }}' "$hpi_tasks"
    rg -Fq 'handler_ensure_hypothesis_self_hosted_service' "$hpi_tasks"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
