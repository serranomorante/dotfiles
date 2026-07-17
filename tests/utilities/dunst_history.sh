#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities notifications shell
# dotfiles-test-case: dunst-history-syntax
# dotfiles-test-case: dunst-history-list-parses-dunstctl-json
# dotfiles-test-case: dunst-history-markdown-parses-dunstctl-json

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
        "id": {"type": "i", "data": 7},
        "appname": {"type": "s", "data": "dotfiles-health-notify"},
        "summary": {"type": "s", "data": "Ansible warning"},
        "body": {"type": "s", "data": "controlled warning"},
        "urgency": {"type": "s", "data": "normal"},
        "category": {"type": "s", "data": "system.ansible"},
        "timestamp": {"type": "x", "data": 35979749793}
      },
      {
        "id": {"type": "i", "data": 8},
        "appname": {"type": "s", "data": "Overseer"},
        "summary": {"type": "s", "data": "Overseer task complete"},
        "body": {"type": "s", "data": "SUCCESS shell fence: cd ~/dotfiles/playbooks"},
        "urgency": {"type": "s", "data": "normal"},
        "category": {"type": "s", "data": "task"},
        "timestamp": {"type": "x", "data": 35979749800}
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
    rg -q $'1\t35979749793\tdotfiles-health-notify\tAnsible warning\tcontrolled warning' "${DOTFILES_TEST_TMP}/rows"
    rg -q $'2\t35979749800\tOverseer\tOverseer task complete\tSUCCESS shell fence: cd ~/dotfiles/playbooks' "${DOTFILES_TEST_TMP}/rows"
    ;;
dunst-history-markdown-parses-dunstctl-json)
    bin=$(write_fake_dunstctl)
    PATH="${bin}:/usr/bin:/bin" "$script_under_test" --markdown >"${DOTFILES_TEST_TMP}/history.md"
    [[ $(rg -c '^## Dunst History$' "${DOTFILES_TEST_TMP}/history.md") -eq 1 ]]
    rg -q '^- \*\*1\.\*\* `35979749793` \*\*dotfiles-health-notify\*\*: Ansible warning$' "${DOTFILES_TEST_TMP}/history.md"
    rg -q '^  controlled warning$' "${DOTFILES_TEST_TMP}/history.md"
    rg -q '^- \*\*2\.\*\* `35979749800` \*\*Overseer\*\*: Overseer task complete$' "${DOTFILES_TEST_TMP}/history.md"
    rg -q '^  SUCCESS shell fence: cd ~/dotfiles/playbooks$' "${DOTFILES_TEST_TMP}/history.md"
    ! rg -q '\{|\}' "${DOTFILES_TEST_TMP}/history.md"
    [[ $(wc -l <"${DOTFILES_TEST_TMP}/history.md") -le 6 ]]
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
