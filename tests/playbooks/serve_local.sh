#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks nginx shell fast
# dotfiles-test-case: serve-local-encodes-file-path-in-url
# dotfiles-test-case: serve-local-directory-url-gets-trailing-slash
# dotfiles-test-case: serve-local-errors-on-missing-path
# dotfiles-test-case: serve-local-errors-on-missing-argument
# dotfiles-test-case: serve-local-starts-nginx-and-local-service
# dotfiles-test-case: nginx-local-config-serves-filesystem-root
# dotfiles-test-case: media-proxy-config-proxies-html-local

# Purpose: Hermetic tests for the `serve-local` helper and the nginx pieces that
#   back it (the user-level nginx config and the system nginx html.local proxy
#   in the 70-for-my-eyes-only media-proxy role). serve-local is exercised with
#   fake `systemctl`/`xdg-open` in PATH so no service or browser is touched; the
#   URL is asserted from the xdg-open log.

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/fixture"
    fakebin="${fixture}/fakebin"
    syslog="${fixture}/systemctl.log"
    xdglog="${fixture}/xdg-open.log"

    rm -rf "$fixture"
    mkdir -p "$fakebin"

    cat >"${fakebin}/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'SYSTEMCTL %s\n' "$*" >> "${SERVE_LOCAL_SYSTEMCTL_LOG}"
for a in "$@"; do
    if [ "$a" = is-active ]; then exit 1; fi
done
exit 0
SH
    cat >"${fakebin}/xdg-open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${SERVE_LOCAL_XDGOPEN_LOG}"
exit 0
SH
    chmod +x "${fakebin}/systemctl" "${fakebin}/xdg-open"
}

run_serve_local() {
    PATH="${fakebin}:/usr/bin:/bin" \
        SERVE_LOCAL_SYSTEMCTL_LOG="$syslog" \
        SERVE_LOCAL_XDGOPEN_LOG="$xdglog" \
        "$DOTFILES_TEST_ROOT/for-my-eyes-only/bin/serve-local" "$@"
}

skip_missing_yaml() {
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
        printf 'SKIP: python yaml module is required to parse the media-proxy role\n' >&2
        exit 77
    fi
}

case "${DOTFILES_TEST_CASE:-}" in
serve-local-encodes-file-path-in-url)
    make_fixture
    mkdir -p "${fixture}/files"
    : >"${fixture}/files/My Doc foo#bar?.html"
    : >"${fixture}/files/áéü.html"

    run_serve_local "${fixture}/files/My Doc foo#bar?.html"
    url1="$(cat "$xdglog")"
    [[ "$url1" == http://html.local/* ]]
    grep -Fq 'My%20Doc%20foo%23bar%3F.html' <<<"$url1"
    refute grep -q ' ' <<<"$url1"

    : >"$xdglog"
    run_serve_local "${fixture}/files/áéü.html"
    url2="$(cat "$xdglog")"
    grep -Fq '%C3%A1%C3%A9%C3%BC.html' <<<"$url2"
    ;;
serve-local-directory-url-gets-trailing-slash)
    make_fixture
    mkdir -p "${fixture}/files/subdir"

    run_serve_local "${fixture}/files/subdir"
    url="$(cat "$xdglog")"
    [[ "$url" == http://html.local/* ]]
    grep -Fq 'subdir/' <<<"$url"
    ;;
serve-local-errors-on-missing-path)
    make_fixture

    if run_serve_local "${fixture}/does-not-exist" >"${fixture}/out" 2>&1; then
        printf 'expected a missing path to fail\n' >&2
        exit 1
    fi
    grep -Fq 'no such path' "${fixture}/out"
    ;;
serve-local-errors-on-missing-argument)
    make_fixture

    if run_serve_local >"${fixture}/out" 2>&1; then
        printf 'expected a missing argument to fail\n' >&2
        exit 1
    fi
    grep -Fq 'Usage: serve-local <path>' "${fixture}/out"
    ;;
serve-local-starts-nginx-and-local-service)
    make_fixture
    mkdir -p "${fixture}/files"
    : >"${fixture}/files/index.html"

    run_serve_local "${fixture}/files/index.html"

    grep -Fq 'SYSTEMCTL is-active --quiet nginx' "$syslog"
    grep -Fq 'SYSTEMCTL start nginx' "$syslog"
    grep -Fq 'SYSTEMCTL --user is-active --quiet nginx-local.service' "$syslog"
    grep -Fq 'SYSTEMCTL --user start nginx-local.service' "$syslog"
    ;;
nginx-local-config-serves-filesystem-root)
    conf="$DOTFILES_TEST_ROOT/for-my-eyes-only/dot-config/nginx-local/nginx.conf"

    grep -Fq 'listen 127.0.0.1:8123;' "$conf"
    grep -Fq 'server_name html.local;' "$conf"
    grep -Fq 'root /;' "$conf"
    grep -Fq 'autoindex off;' "$conf"
    grep -Fq 'try_files $uri =404;' "$conf"
    grep -Fq 'include /etc/nginx/mime.types;' "$conf"
    ;;
media-proxy-config-proxies-html-local)
    skip_missing_yaml
    tasks_file="$DOTFILES_TEST_ROOT/for-my-eyes-only/playbooks/roles/70-for-my-eyes-only/tasks/40-setup-media-proxy.archlinux.yml"

    python3 - "$tasks_file" <<'PY'
import sys
import yaml

with open(sys.argv[1]) as fh:
    tasks = yaml.safe_load(fh)


def find(substr):
    for task in tasks:
        if task.get("name") and substr in task["name"]:
            return task
    raise SystemExit("task not found: %s" % substr)


hosts = find("ensure /etc/hosts entries")
if "html.local" not in (hosts.get("loop") or []):
    raise SystemExit("html.local missing from /etc/hosts loop")

proxy = find("create nginx config for media services")
content = proxy["ansible.builtin.copy"]["content"]
for needle in (
    "server_name html.local;",
    "allow 127.0.0.1;",
    "deny all;",
    "proxy_pass http://127.0.0.1:8123;",
):
    if needle not in content:
        raise SystemExit("missing from nginx proxy config: %s" % needle)

svc = find("ensure nginx-local user service")
unit = svc["ansible.builtin.systemd_service"]
assert unit["name"] == "nginx-local.service"
assert unit["scope"] == "user"
assert unit["state"] == "started"
assert unit["enabled"] is True
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
