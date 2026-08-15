#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: nvim
# dotfiles-test-tags: nvim scripts
# dotfiles-test-case: open-in-nvim-goto-foam-closes-terminal-window
# dotfiles-test-case: open-in-nvim-agent-conversation-uses-agent-tasks
# dotfiles-test-case: open-in-nvim-agent-conversation-falls-back-to-nvr

# Purpose: Verify remote editor actions preserve expected pre-navigation window cleanup.

script_under_test="${DOTFILES_TEST_ROOT}/nvim/bin/open_in_nvim"

make_fake_home() {
    local home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "${home}/dotfiles/term/bin"
    cat >"${home}/dotfiles/term/bin/kitty-window-utils.sh" <<'BASH'
kitty_nvim_servername_from_context() {
    return 1
}

kitty_nvim_servername_from_cwd() {
    printf '/tmp/fake-nvim-%s.sock\n' "${1##*/}"
}
BASH
    printf '%s\n' "$home"
}

make_fake_nvr_bin() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/nvr" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/nvr.args"
BASH
    chmod +x "${bin}/nvr"
    printf '%s\n' "$bin"
}

make_fake_agent_tasks_bin() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/agent-tasks" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf 'NVIM=%s\n' "${AGENT_TASKS_NVIM:-}"
printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/agent-tasks.args"
BASH
    chmod +x "${bin}/agent-tasks"
    printf '%s\n' "$bin"
}

case "${DOTFILES_TEST_CASE:-}" in
open-in-nvim-goto-foam-closes-terminal-window)
    home=$(make_fake_home)
    bin=$(make_fake_nvr_bin)

    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" --servername /tmp/nvim.sock goto_foam_block_by_id todo-sample-agent-task

    python - "${DOTFILES_TEST_TMP}/nvr.args" <<'PY'
import sys

args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert args[:4] == ["--servername", "/tmp/nvim.sock", "--nostart", "-c"], args
assert args[4].startswith("lua "), args
assert "vim.bo.buftype == 'terminal'" in args[4], args
assert "nvim_win_close" in args[4], args
assert args[5:] == ["-c", "GoToFoamBlockById todo-sample-agent-task"], args
PY
    ;;
open-in-nvim-agent-conversation-uses-agent-tasks)
    home=$(make_fake_home)
    bin=$(make_fake_agent_tasks_bin)

    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" --servername /tmp/nvim.sock agent_conversation 019ec503-1d4c >"${DOTFILES_TEST_TMP}/agent-tasks.out" 2>&1

    rg -q -- '^NVIM=/tmp/nvim.sock$' "${DOTFILES_TEST_TMP}/agent-tasks.out"
    rg -q -- '^open --all 019ec503-1d4c$' "${DOTFILES_TEST_TMP}/agent-tasks.args"
    ;;
open-in-nvim-agent-conversation-falls-back-to-nvr)
    home=$(make_fake_home)
    bin=$(make_fake_nvr_bin)

    HOME="$home" PATH="${bin}:/usr/bin:/bin" "$script_under_test" --servername /tmp/nvim.sock agent_conversation 019ec503-1d4c

    python - "${DOTFILES_TEST_TMP}/nvr.args" <<'PY'
import sys

args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert args[:3] == ["--servername", "/tmp/nvim.sock", "--nostart"], args
assert args[3] == "-c", args
assert args[4] == "AgentResumeById 019ec503-1d4c", args
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
