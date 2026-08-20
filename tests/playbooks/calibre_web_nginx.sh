#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks calibre nginx shell fast
# dotfiles-test-case: calibre-web-nginx-does-not-cache-format-endpoints

# Purpose: Hermetic test that the media-proxy role's calibre-web.local server
#   block forces no-store caching (and drops Last-Modified/ETag) for the
#   /show and /download endpoints that serve book formats, so an in-place PDF
#   update is not masked by the browser's HTTP cache.

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse the media-proxy role\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
calibre-web-nginx-does-not-cache-format-endpoints)
    skip_missing_yaml
    media_proxy="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/40-setup-media-proxy.archlinux.yml"

    python3 - "$media_proxy" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)

content = None
for task in tasks:
    if task.get("name") and "create nginx config for media services" in task["name"]:
        content = task["ansible.builtin.copy"]["content"]
        break
if content is None:
    raise SystemExit("nginx proxy task not found")

needles = (
    "server_name calibre-web.local;",
    "location ~ ^/(show|download)/ {",
    "proxy_pass http://127.0.0.1:8083;",
    "proxy_hide_header Cache-Control;",
    "proxy_hide_header Last-Modified;",
    "proxy_hide_header ETag;",
    'add_header Cache-Control "no-store, must-revalidate" always;',
)
for needle in needles:
    if needle not in content:
        raise SystemExit("missing from calibre-web nginx config: %s" % needle)
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
