#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities notifications shell
# dotfiles-test-case: dunst-history-syntax
# dotfiles-test-case: dunst-history-list-parses-dunstctl-json

# Purpose: Verify the Dunst history picker parses dunstctl history output.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/dunst-history"

write_fake_dunstctl() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/dunstctl" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
history)
    cat <<'JSON'
{
  "data": [
    [
      {
        "id": 7,
        "appname": "dotfiles-health-notify",
        "summary": "Ansible warning",
        "body": "controlled warning",
        "urgency": "normal",
        "category": "system.ansible",
        "timestamp": "2026-07-17T16:31:48+02:00"
      }
    ]
  ]
}
JSON
    ;;
*)
    exit 2
    ;;
esac
BASH
    chmod +x "${bin}/dunstctl"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
dunst-history-syntax)
    bash -n "$script_under_test"
    ;;
dunst-history-list-parses-dunstctl-json)
    bin=$(write_fake_dunstctl)
    PATH="${bin}:/usr/bin:/bin" "$script_under_test" --list >"${DOTFILES_TEST_TMP}/rows"
    rg -q $'1\t2026-07-17T16:31:48\\+02:00\tdotfiles-health-notify\tAnsible warning\tcontrolled warning' "${DOTFILES_TEST_TMP}/rows"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
