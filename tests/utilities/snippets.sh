#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities snippets kitty fzf xclip xdotool shell
# dotfiles-test-case: snippets-syntax
# dotfiles-test-case: snippets-panel-pick-pastes-selection
# dotfiles-test-case: snippets-lists-public-and-private

# Purpose: Verify the shared snippet picker metadata display and paste handoff.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/snippets"

make_fake_path() {
    local bin="${DOTFILES_TEST_TMP}/bin"

    mkdir -p "$bin"
    cat >"${bin}/kitten" <<'SH'
#!/usr/bin/env sh
set -eu

case "$1" in
quick-access-terminal)
    shift
    while [ "$#" -gt 0 ]; do
        case $1 in
        env)
            shift
            printf 'panel-start\n' >>"${DOTFILES_TEST_TMP}/events.log"
            env "$@"
            status=$?
            touch "${DOTFILES_TEST_TMP}/panel-closed"
            printf 'panel-closed\n' >>"${DOTFILES_TEST_TMP}/events.log"
            exit "$status"
            ;;
        --instance-group=*|--detach=*|--detach|--override)
            shift
            [ "${1:-}" = "--override" ] && shift || true
            ;;
        *)
            shift
            ;;
        esac
    done
    exit 2
    ;;
@)
    exit 0
    ;;
*)
    exec "$@"
    ;;
esac
SH
    chmod +x "${bin}/kitten"
    cat >"${bin}/systemd-run" <<'SH'
#!/usr/bin/env sh
set -eu

printf 'unexpected systemd-run call: %s\n' "$*" >&2
exit 2
SH
    chmod +x "${bin}/systemd-run"
    cat >"${bin}/fzf" <<'SH'
#!/usr/bin/env sh
set -eu

input_file="${DOTFILES_TEST_TMP}/fzf-input"
cat >"$input_file"
sed -n '1p' "$input_file"
SH
    chmod +x "${bin}/fzf"
    cat >"${bin}/xclip" <<'SH'
#!/usr/bin/env sh
set -eu

cat >"${DOTFILES_TEST_TMP}/clipboard.txt"
printf 'xclip\n' >>"${DOTFILES_TEST_TMP}/events.log"
SH
    chmod +x "${bin}/xclip"
cat >"${bin}/xdotool" <<'SH'
#!/usr/bin/env sh
set -eu

case "$*" in
"getactivewindow")
    count_file="${DOTFILES_TEST_TMP}/active-window-count"
    if [ -f "$count_file" ]; then
        count=$(cat "$count_file")
    else
        count=0
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"

    if [ ! -e "${DOTFILES_TEST_TMP}/panel-closed" ]; then
        printf '%s\n' 1000
    elif [ "$count" -lt 2 ]; then
        printf 'focus-still-picker\n' >>"${DOTFILES_TEST_TMP}/events.log"
        printf '%s\n' 1000
    else
        printf '%s\n' 2000
    fi
    ;;
"getwindowclassname 1000")
    printf '%s\n' "${DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL:-kitty-snippets}"
    ;;
"getwindowclassname 2000")
    printf '%s\n' "${DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL:-brave-browser}"
    ;;
"key --clearmodifiers ctrl+shift+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-terminal\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
"key --clearmodifiers ctrl+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-browser\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
*)
    printf 'unexpected xdotool call: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/xdotool"
    printf '%s\n' "$bin"
}

write_snippet_fixture() {
    local snippets_dir="${DOTFILES_TEST_TMP}/home/dotfiles/utilities/dot-local/share/dotfiles/snippets"

    mkdir -p "$snippets_dir"
    cat >"${snippets_dir}/orchestrate-agent-tasks-reminder" <<'EOF'
# snippet-title: Delegate agent tasks
# snippet-summary: Remind the model to delegate implementation work to child agents, keep listening for follow-up prompts, parallelize with copy-* worktrees, and reuse Chromium/Playwright instances for tests.

Recuerda que tu trabajo es orquestar a los agentes hijos (agent-tasks) de esta sesión, las implementaciones debes delegarlas de modo que quedes libre para seguir recibiendo prompts. Cuando delegues, recuerda quedarte escuchando el state de los agentes hijos de modo que puedas enviar prompts adicionales, o bien responder preguntas y decisiones que estos agentes estén esperando (revisar agent-tasks para más información).

Recuerda que puedes paralelizar el trabajo usando los agentes hijos que están en worktrees de frontend (copy-*) que ya hemos creado con anticipación.

Recuerda que tenemos varias instancias de chromium abiertas en puertos específicos para que puedas paralelizar también los tests usando alguno de los mcps de playwright que hemos creado para esas instancias/perfiles de chromium.
EOF
    printf '%s\n' "$snippets_dir"
}

wait_for_file() {
    local path=$1
    local attempts=${2:-200}
    local attempt

    for ((attempt = 0; attempt < attempts; attempt++)); do
        [ -e "$path" ] && return 0
        sleep 0.05
    done

    return 1
}

case "${DOTFILES_TEST_CASE:-}" in
snippets-syntax)
    sh -n "$script_under_test"
    ;;
snippets-panel-pick-pastes-selection)
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL=brave-browser \
        "$script_under_test"

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    expected_input=$(printf 'public\tDelegate agent tasks\tRemind the model to delegate implementation work to child agents, keep listening for follow-up prompts, parallelize with copy-* worktrees, and reuse Chromium/Playwright instances for tests.\torchestrate-agent-tasks-reminder\t%s\n' "${snippets_dir}/orchestrate-agent-tasks-reminder")
    expected_payload="${DOTFILES_TEST_TMP}/expected-payload"
    sed -n '4,$p' "${snippets_dir}/orchestrate-agent-tasks-reminder" >"$expected_payload"
    grep -Fqx "$expected_input" "${DOTFILES_TEST_TMP}/fzf-input"
    cmp -s "$expected_payload" "${DOTFILES_TEST_TMP}/clipboard.txt"
    grep -Fxq 'key --clearmodifiers ctrl+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    [ ! -e "${DOTFILES_TEST_TMP}/systemd-run.args" ]
    rg -q '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^xclip$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log"
    panel_closed_line=$(rg -n '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    focus_still_picker_line=$(rg -n '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    xclip_line=$(rg -n '^xclip$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    paste_line=$(rg -n '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    [ "$panel_closed_line" -lt "$xclip_line" ]
    [ "$xclip_line" -lt "$focus_still_picker_line" ]
    [ "$focus_still_picker_line" -lt "$paste_line" ]
    [ "$xclip_line" -lt "$paste_line" ]
    ;;
snippets-lists-public-and-private)
    # Regression: when launched without an explicit DOTFILES_SNIPPETS_DIR the
    # picker must enumerate both the public and the private snippet roots, not
    # collapse onto a single "custom" directory.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    private_dir="${DOTFILES_TEST_TMP}/home/dotfiles/for-my-eyes-only/dot-local/share/dotfiles/snippets"
    mkdir -p "$private_dir"
    cat >"${private_dir}/cf-private-snippet" <<'EOF'
# snippet-title: Private snippet
# snippet-summary: A snippet that lives in for-my-eyes-only.

private body text
EOF
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL=brave-browser \
        "$script_under_test"

    wait_for_file "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fq $'public\tDelegate agent tasks\t' "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fq $'private\tPrivate snippet\t' "${DOTFILES_TEST_TMP}/fzf-input"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
